import SwiftData
import SwiftUI

/// Browses a plan one week at a time. Days changed by a dateOverride are marked.
/// When `stored` is set (the active plan), days can be edited: add a task, swipe to delete, clear the day.
struct PlanWeekBrowser: View {
    let plan: Plan
    /// The record to save edits to; nil makes the browser read-only (archived plans).
    var stored: StoredPlan?
    /// When set, shows a link to archived plans (only for the active plan).
    var archivedCount: Int?

    @Environment(\.modelContext) private var modelContext
    @State private var weekStart: LocalDate
    @State private var editRequest: TaskEditRequest?
    @State private var pendingDelete: PendingDelete?
    @State private var clearingDay: LocalDate?
    @State private var resettingDay: LocalDate?
    @State private var editError: String?

    /// A delete that needs a "this date or every week" answer.
    private struct PendingDelete {
        let date: LocalDate
        let index: Int
        let title: String
    }
    private let today = LocalDate.today()
    private let firstWeekday = Calendar.plan.firstWeekday

    init(plan: Plan, stored: StoredPlan? = nil, archivedCount: Int? = nil) {
        self.plan = plan
        self.stored = stored
        self.archivedCount = archivedCount
        let today = LocalDate.today()
        let anchor: LocalDate
        if today < plan.startDate {
            anchor = plan.startDate
        } else if let end = plan.endDate, today > end {
            anchor = end
        } else {
            anchor = today
        }
        _weekStart = State(initialValue: anchor.startOfWeek(firstWeekday: Calendar.plan.firstWeekday))
    }

    private var isEditable: Bool { stored != nil }
    private var weekDays: [ResolvedDay] { plan.days(from: weekStart, count: 7) }
    private var canGoBack: Bool { weekStart > plan.startDate.startOfWeek(firstWeekday: firstWeekday) }
    private var canGoForward: Bool { plan.endDate.map { weekStart.adding(days: 7) <= $0 } ?? true }
    private var todayWeekStart: LocalDate { today.startOfWeek(firstWeekday: firstWeekday) }

    var body: some View {
        List {
            Section {
                LabeledContent("Dates", value: plan.dateRangeText)
                LabeledContent("Tasks", value: plan.taskCountText)
                if let note = plan.timingNote(today: today) {
                    Label(note, systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                weekNavigator
            } footer: {
                if isEditable {
                    Text("Swipe left on a task (or long-press it) to edit or delete it.")
                }
            }

            ForEach(weekDays) { day in
                Section {
                    daySection(day)
                } header: {
                    DayHeader(day: day, isToday: day.date == today)
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
                if let index = request.index {
                    edit { try $0.replaceTask(at: index, on: request.date, with: task, scope: scope) }
                } else {
                    edit { try $0.addTask(task, on: request.date, scope: scope) }
                }
            }
        }
        .confirmationDialog(
            "Delete “\(pendingDelete?.title ?? "")”?",
            isPresented: .init(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { pending in
            Button("Only on \(pending.date.shortText)", role: .destructive) {
                edit { try $0.deleteTask(at: pending.index, on: pending.date, scope: .thisDate) }
            }
            Button("Every \(pending.date.weekday.displayName)", role: .destructive) {
                edit { try $0.deleteTask(at: pending.index, on: pending.date, scope: .everyWeek) }
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
                edit { try $0.resetDay(date) }
            }
        } message: { date in
            Text("\(date.longText) will show the normal \(date.weekday.displayName) tasks again. All changes to this date are removed, including ones from the plan file.")
        }
        .confirmationDialog(
            "Clear this day?",
            isPresented: .init(get: { clearingDay != nil }, set: { if !$0 { clearingDay = nil } }),
            titleVisibility: .visible,
            presenting: clearingDay
        ) { date in
            Button("Remove All Tasks", role: .destructive) {
                edit { try $0.clearDay(date) }
            }
        } message: { date in
            Text("Every task on \(date.longText) will be removed. Other days don't change.")
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

    @ViewBuilder
    private func daySection(_ day: ResolvedDay) -> some View {
        if let note = day.dayNote {
            Text(note).foregroundStyle(.secondary)
        }
        if !day.isInPlan {
            Text("Outside the plan's dates").foregroundStyle(.secondary)
        } else if day.tasks.isEmpty {
            Text("No tasks").foregroundStyle(.secondary)
        }
        ForEach(Array(day.tasks.enumerated()), id: \.offset) { index, task in
            NavigationLink {
                TaskDetailView(task: task)
            } label: {
                TaskRow(task: task)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if isEditable {
                    taskActions(task: task, index: index, date: day.date)
                }
            }
            .contextMenu {
                if isEditable {
                    taskActions(task: task, index: index, date: day.date)
                }
            }
        }
        if isEditable && day.isInPlan {
            HStack(spacing: 16) {
                Button("Add Task", systemImage: "plus.circle") {
                    editRequest = .add(on: day.date)
                }
                Spacer()
                if day.overrideMode != nil {
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
    private func taskActions(task: PlanTask, index: Int, date: LocalDate) -> some View {
        let fromWeeklyPattern: Bool = {
            if case .weeklyPattern = plan.source(ofTaskAt: index, on: date) { return true }
            return false
        }()
        Button("Delete", systemImage: "trash", role: .destructive) {
            if fromWeeklyPattern {
                pendingDelete = PendingDelete(date: date, index: index, title: task.title)
            } else {
                edit { try $0.deleteTask(at: index, on: date, scope: .thisDate) }
            }
        }
        Button("Edit", systemImage: "pencil") {
            editRequest = TaskEditRequest(date: date, index: index, existing: task, allowsEveryWeek: fromWeeklyPattern)
        }
        .tint(.blue)
    }

    private func edit(_ change: (inout Plan) throws -> Void) {
        guard let stored else { return }
        do {
            try PlanStore.update(stored, in: modelContext, change)
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
            .disabled(!canGoBack)

            Spacer()
            VStack(spacing: 2) {
                Text("\(weekStart.monthDayText) – \(weekStart.adding(days: 6).monthDayText)")
                    .font(.headline)
                if weekStart != todayWeekStart && plan.contains(today) {
                    Button("Go to this week") { weekStart = todayWeekStart }
                        .font(.footnote)
                }
            }
            Spacer()

            Button("Next week", systemImage: "chevron.right") {
                weekStart = weekStart.adding(days: 7)
            }
            .labelStyle(.iconOnly)
            .disabled(!canGoForward)
        }
        .buttonStyle(.borderless)
        .imageScale(.large)
    }
}

private struct DayHeader: View {
    let day: ResolvedDay
    let isToday: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(day.date.longText)
            if isToday {
                Text("Today")
                    .font(.caption.bold())
                    .foregroundStyle(.tint)
            }
            Spacer()
            if let mode = day.overrideMode {
                OverrideBadge(mode: mode)
            }
        }
        .textCase(nil)
    }
}

struct TaskRow: View {
    let task: PlanTask

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(task.suggestedTime?.description ?? "--:--")
                .monospacedDigit()
                .foregroundStyle(task.suggestedTime == nil ? .secondary : .primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                Text([task.category, task.durationText].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
