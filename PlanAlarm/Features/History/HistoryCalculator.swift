import Foundation

/// One task in history (a copy of what matters from a `TaskRecord`).
struct HistoryTask: Hashable, Sendable {
    var title: String
    var category: String
    var status: TaskStatus

    /// Categories are compared ignoring case and surrounding spaces ("Gym" = "gym ").
    var categoryKey: String { HistoryCalculator.categoryKey(category) }
}

/// A day that was checked in (or has task records), with its tasks.
struct HistoryDay: Hashable, Sendable {
    var date: LocalDate
    var tasks: [HistoryTask]
    /// False for a day recorded afterwards because it passed without a check-in.
    var checkedIn = true
}

/// How a day went, for the calendar colours and the perfect-day streak.
enum DayKind: String, Sendable {
    /// Every task done.
    case allDone
    /// Some done, some not.
    case partial
    /// Tasks, none done.
    case noneDone
    /// Checked in with no tasks: neutral.
    case restDay
    /// A past day with no check-in, after the app was first used: counts as not done.
    case missed
    /// Today, with tasks still open: neutral until the day is over.
    case inProgress
    /// Nothing to show (before the app was used, today before the check-in, or the future).
    case noData
}

struct Streak: Equatable, Sendable {
    var current = 0
    var best = 0
}

struct Completion: Equatable, Sendable {
    var done = 0
    var total = 0

    /// Done ÷ total, or nil when nothing was due.
    var fraction: Double? { total == 0 ? nil : Double(done) / Double(total) }
}

/// History rules (§8 of the brief), free of UI and storage so they can be tested.
///
/// - Perfect-day streak: consecutive days where every task was done. Skipped, unlogged and missed days
///   break it; rest days (no tasks) neither break nor extend it; today counts only once complete.
/// - Category streak: consecutive days on which that category was scheduled and all its tasks were done,
///   ignoring days it wasn't scheduled; today counts only once that category is complete.
/// - Completion: done ÷ tasks due in the window; today's still-open tasks aren't due yet.
enum HistoryCalculator {
    static func categoryKey(_ category: String) -> String {
        category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// `unscheduled`: past dates with no check-in on which nothing was planned; they count as rest days,
    /// not missed days.
    static func kind(on date: LocalDate, days: [LocalDate: HistoryDay], today: LocalDate,
                     unscheduled: Set<LocalDate> = []) -> DayKind {
        guard let day = days[date] else {
            if let first = days.keys.min(), date > first, date < today {
                if unscheduled.contains(date) { return .restDay }
                return .missed
            }
            return .noData
        }
        let tasks = day.tasks
        guard !tasks.isEmpty else { return .restDay }
        let done = tasks.filter { $0.status == .done }.count
        if done == tasks.count { return .allDone }
        if date == today && tasks.contains(where: { !$0.status.isResolved }) { return .inProgress }
        if done == 0 && !day.checkedIn { return .missed }
        return done == 0 ? .noneDone : .partial
    }

    static func perfectDayStreak(days: [LocalDate: HistoryDay], today: LocalDate,
                                 unscheduled: Set<LocalDate> = []) -> Streak {
        guard let first = days.keys.min(), first <= today else { return Streak() }
        var streak = Streak()
        var date = first
        while date <= today {
            switch kind(on: date, days: days, today: today, unscheduled: unscheduled) {
            case .allDone:
                streak.current += 1
                streak.best = max(streak.best, streak.current)
            case .partial, .noneDone, .missed:
                streak.current = 0
            case .restDay, .inProgress, .noData:
                break
            }
            date = date.adding(days: 1)
        }
        return streak
    }

    /// Streaks per category key.
    static func categoryStreaks(days: [LocalDate: HistoryDay], today: LocalDate) -> [String: Streak] {
        let ordered = days.values.filter { $0.date <= today }.sorted { $0.date < $1.date }
        var streaks: [String: Streak] = [:]
        for day in ordered {
            let byCategory = Dictionary(grouping: day.tasks, by: \.categoryKey)
            for (category, tasks) in byCategory {
                var streak = streaks[category] ?? Streak()
                if tasks.allSatisfy({ $0.status == .done }) {
                    streak.current += 1
                    streak.best = max(streak.best, streak.current)
                } else if day.date == today && tasks.contains(where: { !$0.status.isResolved }) {
                    // Today isn't over for this category yet.
                } else {
                    streak.current = 0
                }
                streaks[category] = streak
            }
        }
        return streaks
    }

    /// Completion over the `window` days ending today, overall and per category key.
    static func completion(days: [LocalDate: HistoryDay], today: LocalDate, window: Int)
        -> (overall: Completion, byCategory: [String: Completion]) {
        var overall = Completion()
        var byCategory: [String: Completion] = [:]
        for offset in 0..<max(1, window) {
            let date = today.adding(days: -offset)
            for task in days[date]?.tasks ?? [] {
                // Today's open tasks aren't due yet.
                if date == today && !task.status.isResolved { continue }
                let isDone = task.status == .done
                overall.total += 1
                overall.done += isDone ? 1 : 0
                byCategory[task.categoryKey, default: Completion()].total += 1
                byCategory[task.categoryKey, default: Completion()].done += isDone ? 1 : 0
            }
        }
        return (overall, byCategory)
    }

    /// The days of a month laid out in weeks: leading nil cells up to the first day, then each date,
    /// padded with nil to whole weeks. `firstWeekday` uses `Calendar` numbering (1 = Sunday).
    static func monthGrid(year: Int, month: Int, firstWeekday: Int) -> [LocalDate?] {
        guard let first = LocalDate(year: year, month: month, day: 1) else { return [] }
        let leading = (first.weekday.calendarWeekday - firstWeekday + 7) % 7
        let count = LocalDate.daysInMonth(year: year, month: month)
        var cells: [LocalDate?] = Array(repeating: nil, count: leading) + (0..<count).map { first.adding(days: $0) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }
}
