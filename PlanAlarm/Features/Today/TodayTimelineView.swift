import SwiftData
import SwiftUI

/// The locked-in day: each task with its time and status.
/// - Tasks that haven't rung yet can have their time changed inline (the alarm moves too).
/// - Open tasks can be marked done or skipped, or given a new time (when ringing, in progress, or overdue).
/// - Done, skipped and not-logged tasks can be undone.
/// - Changes to today in the Plan tab are applied here right away.
struct TodayTimelineView: View {
    let date: LocalDate
    let dayRecord: DayRecord

    @Environment(\.modelContext) private var modelContext
    @Query private var records: [TaskRecord]
    @Query(filter: #Predicate<StoredPlan> { $0.isActive == true }) private var activePlans: [StoredPlan]
    @Query(sort: \ExtraTask.createdAt) private var extras: [ExtraTask]
    @State private var alarms = AlarmService.shared
    @State private var router = AppRouter.shared
    @State private var errorText: String?
    @State private var isConfirmingUnlock = false
    @State private var newTimeFor: TaskRecord?
    @State private var now = Date.now

    init(date: LocalDate, dayRecord: DayRecord) {
        self.date = date
        self.dayRecord = dayRecord
        let key = date.description
        _records = Query(filter: #Predicate<TaskRecord> { $0.date == key }, sort: \TaskRecord.order)
    }

    private var currentPlan: Plan? {
        activePlans.first.flatMap { PlanStore.plan(for: $0) }
    }

    private var currentAgenda: DayAgenda {
        DayAgenda(date: date, plan: currentPlan, extras: extras)
    }

    private var timeline: [TaskRecord] {
        records.sorted { ($0.scheduledFor ?? .distantFuture, $0.order) < ($1.scheduledFor ?? .distantFuture, $1.order) }
    }

    /// An open task with no alarm coming: no time yet, or its time passed without an alarm (e.g. after Undo).
    private func needsTime(_ record: TaskRecord, now: Date) -> Bool {
        record.status == .scheduled
            && (record.scheduledFor ?? .distantPast) <= now
            && alarms.registry.task(forKey: record.alarmKey) == nil
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(date.longText)
                        .font(.title2.bold())
                    if let note = dayRecord.dayNote {
                        Text(note).foregroundStyle(.secondary)
                    }
                    Label("Locked in at \(dayRecord.lockedInAt.formatted(date: .omitted, time: .shortened))",
                          systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                TodayBanners()
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            if !alarms.tasksPendingAcknowledgement.isEmpty {
                Section {
                    Button {
                        router.showPendingTaskIfNeeded()
                    } label: {
                        Label("A task alarm is waiting — open it", systemImage: "alarm.waves.left.and.right.fill")
                            .font(.headline)
                    }
                    .tint(.orange)
                }
            }

            Section("Today") {
                if timeline.isEmpty {
                    Text("Nothing scheduled today.")
                        .foregroundStyle(.secondary)
                }
                ForEach(timeline) { record in
                    TimelineRow(
                        record: record,
                        needsTime: needsTime(record, now: now),
                        onReschedule: { reschedule(record, to: $0) },
                        onLog: { log(record, as: $0) },
                        onUndo: { undo(record) },
                        onNewTime: { newTimeFor = record }
                    )
                }
            }
        }
        .task {
            // Keeps "overdue" states current while the screen is open.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                now = .now
            }
        }
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Unlock Day", systemImage: "lock.open") {
                    isConfirmingUnlock = true
                }
            }
        }
        .confirmationDialog("Unlock today?", isPresented: $isConfirmingUnlock, titleVisibility: .visible) {
            Button("Unlock and Redo Check-in") { unlockDay() }
        } message: {
            Text("Today's task alarms are cancelled and you go back to the morning check-in to plan the day again. Tasks you've already marked done or skipped stay.")
        }
        .sheet(item: $newTimeFor) { record in
            NewTimeSheet(title: record.title) { time in
                reschedule(record, to: time)
            }
        }
        .alert("Couldn't update the task", isPresented: .init(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(errorText ?? "")
        }
        // Changes to today in the Plan tab (or extra tasks) are applied right away.
        .onChange(of: CheckInPlanner.signature(of: currentAgenda), initial: true) {
            syncWithPlan()
        }
    }

    private func syncWithPlan() {
        do {
            let result = try DayStore.sync(date, with: currentAgenda, planDefaultReadSeconds: currentPlan?.defaultReadSeconds,
                                           in: modelContext)
            TaskActions.removed(taskKeys: result.removedKeys)
            TaskActions.scheduleAlarms(for: result.added)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func reschedule(_ record: TaskRecord, to time: Date) {
        guard time > .now else {
            errorText = "Pick a time later than now."
            return
        }
        do {
            try TaskActions.reschedule(record, to: time, in: modelContext)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func undo(_ record: TaskRecord) {
        do {
            try TaskActions.undo(record, in: modelContext)
            now = .now
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func unlockDay() {
        do {
            TaskActions.removed(taskKeys: try DayStore.unlock(date, in: modelContext))
            alarms.updateCheckInReminders()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func log(_ record: TaskRecord, as status: TaskStatus) {
        TaskActions.log(record, as: status, in: modelContext)
    }
}

private struct TimelineRow: View {
    let record: TaskRecord
    let needsTime: Bool
    let onReschedule: (Date) -> Void
    let onLog: (TaskStatus) -> Void
    let onUndo: () -> Void
    let onNewTime: () -> Void

    @State private var pickedTime: Date

    init(record: TaskRecord, needsTime: Bool, onReschedule: @escaping (Date) -> Void,
         onLog: @escaping (TaskStatus) -> Void, onUndo: @escaping () -> Void, onNewTime: @escaping () -> Void) {
        self.record = record
        self.needsTime = needsTime
        self.onReschedule = onReschedule
        self.onLog = onLog
        self.onUndo = onUndo
        self.onNewTime = onNewTime
        _pickedTime = State(initialValue: record.scheduledFor ?? .now)
    }

    /// A scheduled task whose alarm is still ahead: its time can be changed inline.
    private var canChangeTimeInline: Bool {
        record.status == .scheduled && !needsTime && (record.scheduledFor ?? .distantPast) > .now
    }

    /// Ringing, in progress, or overdue: offer a new time.
    private var offersNewTime: Bool {
        needsTime || record.status == .ringing || record.status == .inProgress
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                NavigationLink {
                    if let task = record.task {
                        TaskDetailView(task: task)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.title)
                            .font(.headline)
                            .strikethrough(record.status == .skipped)
                        HStack(spacing: 6) {
                            if needsTime {
                                NeedsTimeChip()
                            } else {
                                StatusChip(status: record.status)
                            }
                            Text(record.category)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                if canChangeTimeInline {
                    DatePicker("Time", selection: $pickedTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .environment(\.calendar, .plan)
                        // Wait until the wheels stop before moving the alarm (each move re-creates its rings).
                        .task(id: pickedTime) {
                            guard pickedTime != record.scheduledFor else { return }
                            try? await Task.sleep(for: .seconds(1))
                            guard !Task.isCancelled else { return }
                            let chosen = pickedTime
                            if chosen <= .now {
                                pickedTime = record.scheduledFor ?? .now // show the real time again
                            }
                            onReschedule(chosen) // a past time is refused with a message
                        }
                } else if let time = record.scheduledFor {
                    Text(time.formatted(date: .omitted, time: .shortened))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                if record.status.isResolved {
                    Button(undoLabel, systemImage: "arrow.uturn.backward.circle") { onUndo() }
                } else {
                    if offersNewTime {
                        Button("New Time", systemImage: "clock.arrow.circlepath") { onNewTime() }
                            .tint(.orange)
                    }
                    Button("Done", systemImage: "checkmark.circle") { onLog(.done) }
                        .tint(.green)
                    Button("Skip", systemImage: "forward.circle") { onLog(.skipped) }
                        .tint(.gray)
                }
            }
            .buttonStyle(.bordered)
            .font(.subheadline)
        }
        .padding(.vertical, 4)
        .onChange(of: record.scheduledFor) {
            pickedTime = record.scheduledFor ?? .now
        }
    }

    private var undoLabel: String {
        switch record.status {
        case .skipped: "Unskip"
        case .unlogged: "Reopen"
        default: "Undo"
        }
    }
}

private struct NeedsTimeChip: View {
    var body: some View {
        Text("Needs a time")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.15), in: Capsule())
            .foregroundStyle(.orange)
    }
}

/// Picks a new time later today for a task.
struct NewTimeSheet: View {
    let title: String
    let onSave: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var time = CheckInPlanner.suggestedTimeLaterToday(now: .now)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("New time", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                } footer: {
                    Text(time > .now ? "The alarm will ring at this time." : "Pick a time later than now.")
                }
            }
            .environment(\.calendar, .plan)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(time)
                        dismiss()
                    }
                    .disabled(time <= .now)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct StatusChip: View {
    let status: TaskStatus

    private var color: Color {
        switch status {
        case .scheduled: .blue
        case .ringing: .orange
        case .inProgress: .purple
        case .done: .green
        case .skipped: .gray
        case .unlogged: .red
        }
    }

    var body: some View {
        Text(status.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}
