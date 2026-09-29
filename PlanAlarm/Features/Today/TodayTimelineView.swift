import SwiftData
import SwiftUI

/// The locked-in day: each task with its time and status. Times of tasks that haven't rung yet can be
/// changed (the alarm moves too), and any open task can be marked done or skipped.
struct TodayTimelineView: View {
    let date: LocalDate
    let dayRecord: DayRecord

    @Environment(\.modelContext) private var modelContext
    @Query private var records: [TaskRecord]
    @State private var alarms = AlarmService.shared
    @State private var router = AppRouter.shared
    @State private var errorText: String?
    @State private var isConfirmingUnlock = false

    init(date: LocalDate, dayRecord: DayRecord) {
        self.date = date
        self.dayRecord = dayRecord
        let key = date.description
        _records = Query(filter: #Predicate<TaskRecord> { $0.date == key }, sort: \TaskRecord.order)
    }

    private var timeline: [TaskRecord] {
        records.sorted { ($0.scheduledFor ?? .distantFuture, $0.order) < ($1.scheduledFor ?? .distantFuture, $1.order) }
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
                AlarmPermissionBanner()
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
                    TimelineRow(record: record) { newTime in
                        reschedule(record, to: newTime)
                    } onLog: { status in
                        log(record, as: status)
                    }
                }
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
        .alert("Couldn't update the task", isPresented: .init(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(errorText ?? "")
        }
    }

    private func reschedule(_ record: TaskRecord, to time: Date) {
        guard time > .now else {
            errorText = "Pick a time later than now."
            return
        }
        guard let task = record.task else { return }
        record.scheduledFor = time
        try? modelContext.save()
        Task {
            await alarms.scheduleTaskAlarm(for: task, key: record.alarmKey, at: time, unlockSeconds: record.unlockSeconds)
        }
    }

    private func unlockDay() {
        do {
            for key in try DayStore.unlock(date, in: modelContext) {
                alarms.acknowledge(taskKey: key)
            }
            alarms.updateCheckInReminders()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func log(_ record: TaskRecord, as status: TaskStatus) {
        do {
            try DayStore.log(record, as: status, in: modelContext)
            alarms.acknowledge(taskKey: record.alarmKey)
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct TimelineRow: View {
    let record: TaskRecord
    let onReschedule: (Date) -> Void
    let onLog: (TaskStatus) -> Void

    @State private var pickedTime: Date

    init(record: TaskRecord, onReschedule: @escaping (Date) -> Void, onLog: @escaping (TaskStatus) -> Void) {
        self.record = record
        self.onReschedule = onReschedule
        self.onLog = onLog
        _pickedTime = State(initialValue: record.scheduledFor ?? .now)
    }

    private var canChangeTime: Bool {
        record.status == .scheduled && (record.scheduledFor ?? .distantPast) > .now
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
                            StatusChip(status: record.status)
                            Text(record.category)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                if canChangeTime {
                    DatePicker("Time", selection: $pickedTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .environment(\.calendar, .plan)
                        .onChange(of: pickedTime) {
                            if pickedTime != record.scheduledFor { onReschedule(pickedTime) }
                        }
                } else if let time = record.scheduledFor {
                    Text(time.formatted(date: .omitted, time: .shortened))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            if !record.status.isResolved {
                HStack {
                    Button("Done", systemImage: "checkmark.circle") { onLog(.done) }
                        .tint(.green)
                    Button("Skip", systemImage: "forward.circle") { onLog(.skipped) }
                        .tint(.gray)
                }
                .buttonStyle(.bordered)
                .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
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
