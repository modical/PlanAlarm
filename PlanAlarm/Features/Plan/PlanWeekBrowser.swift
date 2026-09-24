import SwiftUI

/// Browses a plan one week at a time. Days changed by a dateOverride are marked.
struct PlanWeekBrowser: View {
    let plan: Plan
    /// When set, shows a link to archived plans (only for the active plan).
    var archivedCount: Int?

    @State private var weekStart: LocalDate
    private let today = LocalDate.today()
    private let firstWeekday = Calendar.plan.firstWeekday

    init(plan: Plan, archivedCount: Int? = nil) {
        self.plan = plan
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
            }

            ForEach(weekDays) { day in
                Section {
                    if let note = day.dayNote {
                        Text(note).foregroundStyle(.secondary)
                    }
                    if !day.isInPlan {
                        Text("Outside the plan's dates").foregroundStyle(.secondary)
                    } else if day.tasks.isEmpty {
                        Text("No tasks").foregroundStyle(.secondary)
                    }
                    ForEach(Array(day.tasks.enumerated()), id: \.offset) { _, task in
                        NavigationLink {
                            TaskDetailView(task: task)
                        } label: {
                            TaskRow(task: task)
                        }
                    }
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
