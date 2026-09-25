import Foundation

enum PlanEditError: LocalizedError, Equatable {
    case outsidePlan(LocalDate)
    case taskNotFound
    case unreadablePlan
    case invalidResult(String)

    var errorDescription: String? {
        switch self {
        case .outsidePlan(let date): "\(date) is outside the plan's dates."
        case .taskNotFound: "That task no longer exists on this day."
        case .unreadablePlan: "The saved plan couldn't be read."
        case .invalidResult(let detail): "The edit would make the plan invalid: \(detail)"
        }
    }
}

/// In-app edits. Every edit changes one date only and is stored as a normal dateOverride,
/// so an edited plan is still a plain schema-v1 file.
extension Plan {
    static func empty(name: String, startDate: LocalDate, endDate: LocalDate?) -> Plan {
        Plan(name: name, startDate: startDate, endDate: endDate, defaultReadSeconds: fallbackReadSeconds,
             library: [:], weeklyTemplate: [:], dateOverrides: [:])
    }

    /// Appends a task to one date: extends that date's override, or creates an "add" override.
    mutating func addTask(_ task: PlanTask, on date: LocalDate) throws {
        guard contains(date) else { throw PlanEditError.outsidePlan(date) }
        if var existing = dateOverrides[date] {
            existing.tasks.append(task)
            dateOverrides[date] = existing
        } else {
            dateOverrides[date] = DateOverride(mode: .add, dayNote: nil, tasks: [task])
        }
    }

    /// Removes one task from one date. The date becomes a "replace" override holding the remaining tasks.
    mutating func deleteTask(at index: Int, on date: LocalDate) throws {
        let resolved = day(on: date)
        guard resolved.isInPlan else { throw PlanEditError.outsidePlan(date) }
        guard resolved.tasks.indices.contains(index) else { throw PlanEditError.taskNotFound }
        var remaining = resolved.tasks
        remaining.remove(at: index)
        dateOverrides[date] = DateOverride(mode: .replace, dayNote: resolved.dayNote, tasks: remaining)
    }

    /// Removes every task from one date, keeping its note.
    mutating func clearDay(_ date: LocalDate) throws {
        let resolved = day(on: date)
        guard resolved.isInPlan else { throw PlanEditError.outsidePlan(date) }
        dateOverrides[date] = DateOverride(mode: .replace, dayNote: resolved.dayNote, tasks: [])
    }
}
