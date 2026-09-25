import Foundation

enum PlanEditError: LocalizedError, Equatable {
    case outsidePlan(LocalDate)
    case taskNotFound
    case notInWeeklyPattern
    case nothingToReset
    case unreadablePlan
    case invalidResult(String)

    var errorDescription: String? {
        switch self {
        case .outsidePlan(let date): "\(date) is outside the plan's dates."
        case .taskNotFound: "That task no longer exists on this day."
        case .notInWeeklyPattern: "This task was added to this date only, so it can only be changed for this date."
        case .nothingToReset: "This date already follows the normal weekly pattern."
        case .unreadablePlan: "The saved plan couldn't be read."
        case .invalidResult(let detail): "The edit would make the plan invalid: \(detail)"
        }
    }
}

/// Whether an edit changes one calendar date or the repeating weekly pattern.
enum EditScope: Sendable {
    case thisDate
    case everyWeek
}

/// Where a task shown on a date comes from.
enum TaskSource: Equatable, Sendable {
    /// The weekday's weeklyTemplate entry, at this index.
    case weeklyPattern(index: Int)
    /// That date's own dateOverride, at this index.
    case thisDateOnly(index: Int)
}

/// In-app edits. They are stored as ordinary weeklyTemplate entries and dateOverrides,
/// so an edited plan is still a plain schema-v1 file.
///
/// A date with its own "replace" override keeps its own tasks when the weekly pattern changes.
extension Plan {
    static func empty(name: String, startDate: LocalDate, endDate: LocalDate?) -> Plan {
        Plan(name: name, startDate: startDate, endDate: endDate, defaultReadSeconds: fallbackReadSeconds,
             library: [:], weeklyTemplate: [:], dateOverrides: [:])
    }

    func source(ofTaskAt index: Int, on date: LocalDate) -> TaskSource? {
        let resolved = day(on: date)
        guard resolved.isInPlan, resolved.tasks.indices.contains(index) else { return nil }
        let templateCount = weeklyTemplate[date.weekday]?.tasks.count ?? 0
        switch dateOverrides[date]?.mode {
        case nil:
            return .weeklyPattern(index: index)
        case .add?:
            return index < templateCount ? .weeklyPattern(index: index) : .thisDateOnly(index: index - templateCount)
        case .replace?:
            return .thisDateOnly(index: index)
        }
    }

    // MARK: Adding

    /// `.thisDate`: extends that date's override, or creates an "add" override.
    /// `.everyWeek`: appends to the weekday's pattern (and to this date too, if it has its own task list).
    mutating func addTask(_ task: PlanTask, on date: LocalDate, scope: EditScope = .thisDate) throws {
        guard contains(date) else { throw PlanEditError.outsidePlan(date) }
        switch scope {
        case .thisDate:
            if var existing = dateOverrides[date] {
                existing.tasks.append(task)
                dateOverrides[date] = existing
            } else {
                dateOverrides[date] = DateOverride(mode: .add, dayNote: nil, tasks: [task])
            }
        case .everyWeek:
            weeklyTemplate[date.weekday, default: DayTemplate(dayNote: nil, tasks: [])].tasks.append(task)
            if dateOverrides[date]?.mode == .replace {
                dateOverrides[date]?.tasks.append(task)
            }
        }
    }

    // MARK: Deleting and editing

    mutating func deleteTask(at index: Int, on date: LocalDate, scope: EditScope = .thisDate) throws {
        try changeTask(at: index, on: date, scope: scope) { tasks, position in
            tasks.remove(at: position)
        }
    }

    mutating func replaceTask(at index: Int, on date: LocalDate, with task: PlanTask, scope: EditScope = .thisDate) throws {
        try changeTask(at: index, on: date, scope: scope) { tasks, position in
            tasks[position] = task
        }
    }

    /// Removes every task from one date, keeping its note.
    mutating func clearDay(_ date: LocalDate) throws {
        let resolved = day(on: date)
        guard resolved.isInPlan else { throw PlanEditError.outsidePlan(date) }
        dateOverrides[date] = DateOverride(mode: .replace, dayNote: resolved.dayNote, tasks: [])
    }

    /// Removes a date's own changes, so it follows the weekly pattern again.
    mutating func resetDay(_ date: LocalDate) throws {
        guard contains(date) else { throw PlanEditError.outsidePlan(date) }
        guard dateOverrides.removeValue(forKey: date) != nil else { throw PlanEditError.nothingToReset }
    }

    /// Applies `change` to the right task list for the scope and where the task comes from.
    private mutating func changeTask(at index: Int, on date: LocalDate, scope: EditScope,
                                     _ change: (inout [PlanTask], Int) -> Void) throws {
        guard contains(date) else { throw PlanEditError.outsidePlan(date) }
        guard let source = source(ofTaskAt: index, on: date) else { throw PlanEditError.taskNotFound }
        switch (scope, source) {
        case (.everyWeek, .weeklyPattern(let position)):
            change(&weeklyTemplate[date.weekday, default: DayTemplate(dayNote: nil, tasks: [])].tasks, position)
        case (.everyWeek, .thisDateOnly):
            throw PlanEditError.notInWeeklyPattern
        case (.thisDate, .thisDateOnly(let position)):
            change(&dateOverrides[date, default: DateOverride(mode: .add, dayNote: nil, tasks: [])].tasks, position)
        case (.thisDate, .weeklyPattern):
            // The date gets its own copy of the day with the change applied.
            let resolved = day(on: date)
            var tasks = resolved.tasks
            change(&tasks, index)
            dateOverrides[date] = DateOverride(mode: .replace, dayNote: resolved.dayNote, tasks: tasks)
        }
    }
}
