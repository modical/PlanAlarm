import Foundation

/// The tasks and note for one calendar day, after applying the weekly template and date overrides.
struct ResolvedDay: Hashable, Sendable, Identifiable {
    var date: LocalDate
    /// False when the date is before startDate or after endDate.
    var isInPlan: Bool
    var dayNote: String?
    var tasks: [PlanTask]
    /// Set when a dateOverride changed this day.
    var overrideMode: DateOverride.Mode?

    var id: LocalDate { date }
    var isRestDay: Bool { isInPlan && tasks.isEmpty }
}

extension Plan {
    func contains(_ date: LocalDate) -> Bool {
        date >= startDate && (endDate.map { date <= $0 } ?? true)
    }

    /// Weekday template first, then the date's override: "replace" swaps the whole day
    /// (tasks and dayNote), "add" appends tasks and replaces the dayNote only if one is given.
    func day(on date: LocalDate) -> ResolvedDay {
        guard contains(date) else {
            return ResolvedDay(date: date, isInPlan: false, dayNote: nil, tasks: [], overrideMode: nil)
        }
        let template = weeklyTemplate[date.weekday]
        var day = ResolvedDay(date: date, isInPlan: true, dayNote: template?.dayNote,
                              tasks: template?.tasks ?? [], overrideMode: nil)
        if let override = dateOverrides[date] {
            day.overrideMode = override.mode
            switch override.mode {
            case .replace:
                day.dayNote = override.dayNote
                day.tasks = override.tasks
            case .add:
                if let note = override.dayNote { day.dayNote = note }
                day.tasks += override.tasks
            }
        }
        return day
    }

    func days(from start: LocalDate, count: Int) -> [ResolvedDay] {
        (0..<count).map { day(on: start.adding(days: $0)) }
    }

    var firstWeek: [ResolvedDay] { days(from: startDate, count: 7) }

    /// Number of days in the plan, or nil if it is open-ended.
    var lengthInDays: Int? {
        endDate.map { startDate.days(until: $0) + 1 }
    }

    /// Task occurrences across the whole plan; nil for open-ended (or absurdly long) plans.
    var totalScheduledTasks: Int? {
        guard let length = lengthInDays, length <= 3_660 else { return nil }
        return days(from: startDate, count: length).reduce(0) { $0 + $1.tasks.count }
    }

    /// Tasks in one week of the weekly template (ignoring overrides).
    var tasksPerTemplateWeek: Int {
        weeklyTemplate.values.reduce(0) { $0 + $1.tasks.count }
    }
}
