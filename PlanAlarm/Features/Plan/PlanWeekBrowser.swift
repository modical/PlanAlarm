import SwiftData
import SwiftUI

/// Browses days one week at a time. Days changed by a dateOverride are marked.
///
/// When editable (the active plan, or no plan at all), every day can be edited: inside the plan's dates
/// edits go into the plan; outside them (or with no plan) tasks are kept in the app as `ExtraTask`s.
struct PlanWeekBrowser: View {
    let plan: Plan?
    /// The record that plan edits are saved to (the active plan).
    var stored: StoredPlan?
    var isEditable: Bool
    /// When set, shows a link to archived plans.
    var archivedCount: Int?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExtraTask.createdAt) private var allExtras: [ExtraTask]
    @Query private var dayRecords: [DayRecord]
    @Query(sort: \TaskRecord.order) private var taskRecords: [TaskRecord]
    @State private var weekStart: LocalDate
    @State private var deletingRecord: TaskRecord?
    @State private var editRequest: TaskEditRequest?
    @State private var pendingDelete: PendingDelete?
    @State private var clearingDay: LocalDate?
    @State private var resettingDay: LocalDate?
    @State private var editError: String?
    private let today = LocalDate.today()
    private let firstWeekday = Calendar.plan.firstWeekday

    /// A delete that needs a "this date or every week" answer.
    private struct PendingDelete {
        let date: LocalDate
        let index: Int
        let title: String
    }

    init(plan: Plan?, stored: StoredPlan? = nil, isEditable: Bool, archivedCount: Int? = nil) {
        self.plan = plan
        self.stored = stored
        self.isEditable = isEditable
        self.archivedCount = archivedCount
        let today = LocalDate.today()
        var anchor = today
        if let plan, !isEditable {
            // Archived plans open on their own dates.
            if today < plan.startDate {
                anchor = plan.startDate
            } else if let end = plan.endDate, today > end {
                anchor = end
            }
        }
        _weekStart = State(initialValue: anchor.startOfWeek(firstWeekday: Calendar.plan.firstWeekday))
    }

    private var extras: [ExtraTask] { isEditable ? allExtras : [] }
    private var weekAgendas: [DayAgenda] {
        (0..<7).map { DayAgenda(date: weekStart.adding(days: $0), plan: plan, extras: extras) }
    }
    private var todayWeekStart: LocalDate { today.startOfWeek(firstWeekday: firstWeekday) }

    /// Whether edits on this date go into the plan (rather than into the app's extra tasks).
    private func editsGoIntoPlan(on date: LocalDate) -> Bool {
        stored != nil && (plan?.contains(date) ?? false)
    }

    /// Past days that were checked in, with what was recorded. They're shown as they happened, whatever
    /// the plan says now (the active plan's browser only; archived plans show the plan itself).
    private var recordedPastDays: [String: (note: String?, records: [TaskRecord], checkedIn: Bool)] {
        guard isEditable else { return [:] }
        let todayKey = today.description
        var result: [String: (note: String?, records: [TaskRecord], checkedIn: Bool)] = [:]
        for day in dayRecords where day.date < todayKey {
            result[day.date] = (day.dayNote, [], day.checkedIn)
        }
        for record in taskRecords where record.date < todayKey {
            result[record.date, default: (nil, [], true)].records.append(record)
        }
        return result
    }

    var body: some View {
        List {
            Section {
                if let plan {
                    LabeledContent("Dates", value: plan.dateRangeText)
                    LabeledContent("Tasks", value: plan.taskCountText)
                    if let note = plan.timingNote(today: today) {
                        Label(note, systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No plan loaded. You can still add tasks to any day, or bring in a plan:")
                        .foregroundStyle(.secondary)
                    ImportPlanButtons()
                }
            }

            Section {
                weekNavigator
            } footer: {
                if isEditable {
                    Text("Swipe left on a task (or long-press it) to edit or delete it. Past days you checked in show what happened and never change with the plan; you can only delete their tasks.")
                }
            }

            let recorded = recordedPastDays
            ForEach(weekAgendas) { agenda in
                let past = recorded[agenda.day.date.description]
                Section {
                    if let past {
                        recordedDaySection(date: agenda.day.date, note: past.note, records: past.records)
                    } else {
                        daySection(agenda)
                    }
                } header: {
                    DayHeader(day: agenda.day, isToday: agenda.day.date == today, isRecorded: past != nil,
                              wasCheckedIn: past?.checkedIn ?? true)
                }
            }

            if let archivedCount {
                Section {
                    NavigationLink {
                        ArchivedPlansView()
                    } label: {
                        LabeledContent("Archived plans", value: "\(archivedCount)")
                    }
                }
            }
        }
        .sheet(item: $editRequest) { request in
            TaskEditorView(request: request, plan: plan) { task, scope in
                save(task, scope: scope, for: request)
            }
        }
        .confirmationDialog(
            "Delete “\(pendingDelete?.title ?? "")”?",
            isPresented: .init(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { pending in
            Button("Only on \(pending.date.shortText)", role: .destructive) {
                editPlan { try $0.deleteTask(at: pending.index, on: pending.date, scope: .thisDate) }
            }
            Button("Every \(pending.date.weekday.displayName)", role: .destructive) {
                editPlan { try $0.deleteTask(at: pending.index, on: pending.date, scope: .everyWeek) }
            }
        } message: { pending in
            Text("“Every \(pending.date.weekday.displayName)” doesn't change dates you edited one by one.")
        }
        .confirmationDialog(
            "Reset this day?",
            isPresented: .init(get: { resettingDay != nil }, set: { if !$0 { resettingDay = nil } }),
            titleVisibility: .visible,
            presenting: resettingDay
        ) { date in
            Button("Reset to Normal \(date.weekday.displayName)", role: .destructive) {
                editPlan { try $0.resetDay(date) }
            }
        } message: { date in
            Text("\(date.longText) will show the normal \(date.weekday.displayName) tasks again. All plan changes to this date are removed, including ones from the plan file.")
        }
        .confirmationDialog(
            "Clear this day?",
            isPresented: .init(get: { clearingDay != nil }, set: { if !$0 { clearingDay = nil } }),
            titleVisibility: .visible,
            presenting: clearingDay
        ) { date in
            Button("Remove All Tasks", role: .destructive) {
                clear(date)
            }
        } message: { date in
            Text("Every task on \(date.longText) will be removed. Other days don't change.")
        }
        .confirmationDialog(
            "Delete “\(deletingRecord?.title ?? "")”?",
            isPresented: .init(get: { deletingRecord != nil }, set: { if !$0 { deletingRecord = nil } }),
            titleVisibility: .visible,
            presenting: deletingRecord
        ) { record in
            Button("Delete from \(LocalDate(isoString: record.date)?.shortText ?? record.date)", role: .destructive) {
                deletePastRecord(record)
            }
        } message: { _ in
            Text("It's removed from that day and from your history. Nothing else changes.")
        }
        .alert("Couldn't change the plan", isPresented: .init(
            get: { editError != nil },
            set: { if !$0 { editError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(editError ?? "")
        }
    }

    /// A past, checked-in day: what was recorded, read-only except for deleting a task.
    @ViewBuilder
    private func recordedDaySection(date: LocalDate, note: String?, records: [TaskRecord]) -> some View {
        if let note {
            Text(note).foregroundStyle(.secondary)
        }
        if records.isEmpty {
            Text("Rest day: nothing was planned").foregroundStyle(.secondary)
        }
        ForEach(records.sorted { ($0.scheduledFor ?? .distantFuture, $0.order) < ($1.scheduledFor ?? .distantFuture, $1.order) }) { record in
            NavigationLink {
                if let task = record.task {
                    TaskDetailView(task: task)
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(record.scheduledFor.map { $0.formatted(date: .omitted, time: .shortened) } ?? "--:--")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.title)
                            .strikethrough(record.status == .skipped)
                        StatusChip(status: record.status)
                    }
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    deletingRecord = record
                }
            }
            .contextMenu {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    deletingRecord = record
                }
            }
        }
    }

    private func deletePastRecord(_ record: TaskRecord) {
        let key = record.alarmKey
        perform { try DayStore.deleteRecord(record, in: modelContext) }
        TaskActions.removed(taskKeys: [key])
    }

    @ViewBuilder
    private func daySection(_ agenda: DayAgenda) -> some View {
        let day = agenda.day
        // Past days can't be planned any more; days you checked in are shown by `recordedDaySection`.
        let canEdit = isEditable && day.date >= today
        if let note = day.dayNote {
            Text(note).foregroundStyle(.secondary)
        }
        if day.tasks.isEmpty {
            Text(plan != nil && !day.isInPlan ? "No tasks · outside the plan's dates" : "No tasks")
                .foregroundStyle(.secondary)
        } else if isEditable && day.date < today {
            Text("Not checked in").font(.caption).foregroundStyle(.secondary)
        }
        ForEach(Array(day.tasks.enumerated()), id: \.offset) { index, task in
            let extra = agenda.extra(at: index)
            NavigationLink {
                TaskDetailView(task: task)
            } label: {
                TaskRow(task: task, note: extra == nil ? nil : "added in the app")
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if canEdit {
                    taskActions(task: task, index: index, date: day.date, extra: extra)
                }
            }
            .contextMenu {
                if canEdit {
                    taskActions(task: task, index: index, date: day.date, extra: extra)
                }
            }
        }
        if canEdit {
            HStack(spacing: 16) {
                Button("Add Task", systemImage: "plus.circle") {
                    let intoPlan = editsGoIntoPlan(on: day.date)
                    editRequest = TaskEditRequest(date: day.date, target: intoPlan ? .newPlanTask : .newExtraTask,
                                                  existing: nil, allowsEveryWeek: intoPlan)
                }
                Spacer()
                if day.overrideMode != nil && stored != nil {
                    Button("Reset", systemImage: "arrow.uturn.backward.circle") {
                        resettingDay = day.date
                    }
                }
                if !day.tasks.isEmpty {
                    Button("Clear Day", systemImage: "xmark.circle", role: .destructive) {
                        clearingDay = day.date
                    }
                    .foregroundStyle(.red)
                }
            }
            .buttonStyle(.borderless)
            .font(.subheadline)
        }
    }

    @ViewBuilder
    private func taskActions(task: PlanTask, index: Int, date: LocalDate, extra: ExtraTask?) -> some View {
        let fromWeeklyPattern: Bool = {
            guard extra == nil, stored != nil, case .weeklyPattern = plan?.source(ofTaskAt: index, on: date) else { return false }
            return true
        }()
        Button("Delete", systemImage: "trash", role: .destructive) {
            if let extra {
                deleteExtras([extra])
            } else if fromWeeklyPattern {
                pendingDelete = PendingDelete(date: date, index: index, title: task.title)
            } else {
                editPlan { try $0.deleteTask(at: index, on: date, scope: .thisDate) }
            }
        }
        Button("Edit", systemImage: "pencil") {
            let target: TaskEditRequest.Target = extra.map { .extraTask($0) } ?? .planTask(index: index)
            editRequest = TaskEditRequest(date: date, target: target, existing: task, allowsEveryWeek: fromWeeklyPattern)
        }
        .tint(.blue)
    }

    // MARK: - Saving

    private func save(_ task: PlanTask, scope: EditScope, for request: TaskEditRequest) {
        switch request.target {
        case .newPlanTask:
            editPlan { try $0.addTask(task, on: request.date, scope: scope) }
        case .planTask(let index):
            editPlan { try $0.replaceTask(at: index, on: request.date, with: task, scope: scope) }
        case .newExtraTask:
            perform { try ExtraTaskStore.add(task, on: request.date, in: modelContext) }
        case .extraTask(let extra):
            perform { try ExtraTaskStore.update(extra, with: task, in: modelContext) }
        }
    }

    private func clear(_ date: LocalDate) {
        let agenda = DayAgenda(date: date, plan: plan, extras: extras)
        if agenda.planTaskCount > 0 {
            editPlan { try $0.clearDay(date) }
        }
        if !agenda.extras.isEmpty {
            deleteExtras(agenda.extras)
        }
    }

    private func deleteExtras(_ items: [ExtraTask]) {
        perform { try ExtraTaskStore.delete(items, in: modelContext) }
    }

    private func editPlan(_ change: (inout Plan) throws -> Void) {
        guard let stored else { return }
        perform { try PlanStore.update(stored, in: modelContext, change) }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            editError = error.localizedDescription
        }
    }

    private var weekNavigator: some View {
        HStack {
            Button("Previous week", systemImage: "chevron.left") {
                weekStart = weekStart.adding(days: -7)
            }
            .labelStyle(.iconOnly)

            Spacer()
            VStack(spacing: 2) {
                Text("\(weekStart.monthDayText) – \(weekStart.adding(days: 6).monthDayText)")
                    .font(.headline)
                if weekStart != todayWeekStart {
                    Button("Go to this week") { weekStart = todayWeekStart }
                        .font(.footnote)
                }
            }
            Spacer()

            Button("Next week", systemImage: "chevron.right") {
                weekStart = weekStart.adding(days: 7)
            }
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .imageScale(.large)
    }
}

private struct DayHeader: View {
    let day: ResolvedDay
    let isToday: Bool
    /// A past day shown as it was recorded (not from the plan).
    var isRecorded = false
    /// For a recorded day: whether it was checked in, or recorded afterwards.
    var wasCheckedIn = true

    var body: some View {
        HStack(spacing: 8) {
            Text(day.date.longText)
            if isToday {
                Text("Today")
                    .font(.caption.bold())
                    .foregroundStyle(.tint)
            }
            Spacer()
            if isRecorded {
                Label(wasCheckedIn ? "Checked in" : "No check-in", systemImage: "lock.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            } else if let mode = day.overrideMode {
                OverrideBadge(mode: mode)
            }
        }
        .textCase(nil)
    }
}

struct TaskRow: View {
    let task: PlanTask
    var note: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(task.suggestedTime?.description ?? "--:--")
                .monospacedDigit()
                .foregroundStyle(task.suggestedTime == nil ? .secondary : .primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                Text([task.category, task.durationText, note].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
