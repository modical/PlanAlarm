import SwiftData
import SwiftUI

/// The morning check-in: confirm yesterday's leftovers, choose today's times, and lock in the day.
struct CheckInView: View {
    let date: LocalDate

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<StoredPlan> { $0.isActive == true }) private var activePlans: [StoredPlan]
    @Query(sort: \ExtraTask.createdAt) private var extras: [ExtraTask]
    @State private var alarms = AlarmService.shared

    @State private var hasLoaded = false
    @State private var items: [CheckInItem] = []
    @State private var dayNote: String?
    @State private var planName: String?
    @State private var carryOver: [TaskRecord] = []
    @State private var answers: [UUID: TaskStatus] = [:]
    @State private var isLockingIn = false
    @State private var errorText: String?

    private var overlaps: [Int: String] { CheckInPlanner.overlaps(in: items) }
    private var unansweredCount: Int { carryOver.filter { answers[$0.id] == nil }.count }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(date.longText)
                        .font(.title2.bold())
                    if let dayNote {
                        Text(dayNote)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                AlarmPermissionBanner()
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            if !carryOver.isEmpty {
                Section {
                    ForEach(carryOver) { record in
                        CarryOverRow(record: record, answer: Binding(
                            get: { answers[record.id] },
                            set: { answers[record.id] = $0 }
                        ))
                    }
                } header: {
                    Text("Did you do these?")
                } footer: {
                    Text("Yesterday's tasks that weren't marked done or skipped.")
                }
            }

            Section {
                if items.isEmpty {
                    Text("Nothing scheduled today. Lock in to stop the check-in reminder.")
                        .foregroundStyle(.secondary)
                }
                ForEach($items) { $item in
                    CheckInRow(item: $item, overlapsWith: overlaps[item.id])
                }
            } header: {
                Text("Today's tasks")
            } footer: {
                if !items.isEmpty {
                    Text("Each task gets an alarm at its time. Set a time for every task, or skip it for today.")
                }
            }
        }
        .navigationTitle("Morning Check-in")
        .safeAreaInset(edge: .bottom) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                lockInBar(now: context.date)
            }
        }
        .alert("Couldn't lock in the day", isPresented: .init(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(errorText ?? "")
        }
        .onAppear(perform: load)
    }

    private func lockInBar(now: Date) -> some View {
        let reason = CheckInPlanner.blockingReason(items: items, unansweredCarryOver: unansweredCount, now: now)
        return VStack(spacing: 8) {
            if let reason {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                lockIn()
            } label: {
                Label("Lock In My Day", systemImage: "lock.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(reason != nil || isLockingIn)
        }
        .padding()
        .background(.bar)
    }

    /// Builds the items once, so edits during the check-in aren't reset by view updates.
    private func load() {
        guard !hasLoaded else { return }
        hasLoaded = true
        let stored = activePlans.first
        let plan = stored.flatMap { PlanStore.plan(for: $0) }
        let agenda = DayAgenda(date: date, plan: plan, extras: extras)
        items = CheckInPlanner.items(for: agenda, planDefaultReadSeconds: plan?.defaultReadSeconds, now: .now)
        dayNote = agenda.day.dayNote
        planName = plan?.name

        let yesterday = date.adding(days: -1)
        // Anything older than yesterday is no longer asked about.
        for key in DayStore.markUnlogged(before: yesterday, in: modelContext) {
            alarms.acknowledge(taskKey: key)
        }
        carryOver = DayStore.unresolvedRecords(on: yesterday, in: modelContext)
    }

    private func lockIn() {
        isLockingIn = true
        Task {
            defer { isLockingIn = false }
            do {
                for record in carryOver {
                    if let answer = answers[record.id] {
                        try DayStore.log(record, as: answer, in: modelContext)
                        alarms.acknowledge(taskKey: record.alarmKey)
                    }
                }
                let records = try DayStore.lockIn(date: date, dayNote: dayNote, planName: planName, items: items, in: modelContext)
                for record in records where record.status == .scheduled {
                    guard let task = record.task, let time = record.scheduledFor else { continue }
                    await alarms.scheduleTaskAlarm(for: task, key: record.alarmKey, at: time, unlockSeconds: record.unlockSeconds)
                }
                alarms.updateCheckInReminders()
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}

private struct CheckInRow: View {
    @Binding var item: CheckInItem
    let overlapsWith: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.task.title)
                        .font(.headline)
                        .strikethrough(item.isSkipped)
                        .foregroundStyle(item.isSkipped ? .secondary : .primary)
                    Text([item.task.category, item.task.durationText, item.isExtra ? "added in the app" : nil]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                timeControl
            }
            Toggle("Skip today", isOn: $item.isSkipped)
                .font(.subheadline)
            if item.timeWasMoved && !item.isSkipped, let time = item.time {
                Label("Its time had already passed, so it's moved to \(time.formatted(date: .omitted, time: .shortened)).",
                      systemImage: "clock.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let overlapsWith, !item.isSkipped {
                Label("Overlaps with “\(overlapsWith)”", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(item.timeWasMoved && !item.isSkipped ? Color.orange.opacity(0.1) : nil)
    }

    @ViewBuilder
    private var timeControl: some View {
        if item.isSkipped {
            Text("Skipped")
                .foregroundStyle(.secondary)
        } else if item.time != nil {
            DatePicker("Time", selection: Binding(
                get: { item.time ?? .now },
                set: { item.time = $0; item.timeWasMoved = false }
            ), displayedComponents: .hourAndMinute)
            .labelsHidden()
            .environment(\.calendar, .plan)
        } else {
            Button("Set time") {
                item.time = CheckInPlanner.defaultNewTime(now: .now)
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct CarryOverRow: View {
    let record: TaskRecord
    @Binding var answer: TaskStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(record.title)
                .font(.headline)
            if let time = record.scheduledFor {
                Text("Yesterday at \(time.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker("Answer", selection: $answer) {
                Text("Done").tag(TaskStatus?.some(.done))
                Text("Skipped").tag(TaskStatus?.some(.skipped))
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 4)
    }
}
