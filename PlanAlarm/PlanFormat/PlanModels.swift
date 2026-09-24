import Foundation

/// A validated plan (schema version 1). Built only by `PlanParser`.
struct Plan: Hashable, Sendable {
    static let supportedSchemaVersion = 1
    static let fallbackReadSeconds = 30

    var name: String
    var startDate: LocalDate
    /// `nil` means the plan is open-ended.
    var endDate: LocalDate?
    var defaultReadSeconds: Int
    /// Library entries, fully resolved (keyed by their taskLibrary key).
    var library: [String: PlanTask]
    var weeklyTemplate: [Weekday: DayTemplate]
    var dateOverrides: [LocalDate: DateOverride]
}

/// One task as it appears on a day, with taskRef overrides and readSeconds fallbacks already applied.
struct PlanTask: Hashable, Sendable {
    /// The taskLibrary key this task came from, if any.
    var taskRef: String?
    var title: String
    var category: String
    var summary: String?
    var sections: [TaskSection]
    var durationMinutes: Int?
    var readSeconds: Int
    var suggestedTime: TimeOfDay?
}

struct TaskSection: Hashable, Sendable {
    var title: String
    var items: [String]
}

struct DayTemplate: Hashable, Sendable {
    var dayNote: String?
    var tasks: [PlanTask]
}

struct DateOverride: Hashable, Sendable {
    enum Mode: String, Sendable {
        /// Append tasks to the weekday's template (dayNote replaced only if given).
        case add
        /// Use only this override's tasks and dayNote for the day.
        case replace
    }

    var mode: Mode
    var dayNote: String?
    var tasks: [PlanTask]
}
