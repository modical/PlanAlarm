import Foundation

/// How to begin a plan whose start date has already passed (chosen in the import preview).
struct PlanStartChoice: Hashable {
    enum Mode: Hashable {
        /// Keep the plan's dates and pick up where it is now; earlier plan days are skipped.
        case continuePlan
        /// Move the whole plan so its first day is the chosen date.
        case restartFromDayOne
    }

    enum Day: Hashable {
        case today, tomorrow, other
    }

    var mode: Mode
    var day: Day = .today
    /// Used when `day` is `.other`.
    var otherDate: LocalDate

    /// The default for `plan`: continue it from today, or, if it has already ended, start it again from
    /// day 1 today.
    init(for plan: Plan, today: LocalDate) {
        let hasEnded = plan.endDate.map { $0 < today } ?? false
        mode = hasEnded ? .restartFromDayOne : .continuePlan
        otherDate = today.adding(days: 2)
    }

    /// Only plans whose first day is already in the past need a choice.
    static func isNeeded(for plan: Plan, today: LocalDate) -> Bool {
        plan.startDate < today
    }

    func startDate(today: LocalDate) -> LocalDate {
        switch day {
        case .today: today
        case .tomorrow: today.adding(days: 1)
        case .other: max(otherDate, today)
        }
    }

    /// The plan as it will be used, or nil when continuing from a date after the plan has ended.
    func apply(to plan: Plan, today: LocalDate) -> Plan? {
        let start = startDate(today: today)
        switch mode {
        case .continuePlan: return plan.continuing(from: start)
        case .restartFromDayOne: return plan.restarting(on: start)
        }
    }
}
