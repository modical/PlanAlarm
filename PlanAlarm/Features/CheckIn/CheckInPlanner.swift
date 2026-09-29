import Foundation

/// One task on the morning check-in screen.
struct CheckInItem: Identifiable, Hashable {
    let id: Int
    var task: PlanTask
    /// True for tasks added in the app rather than from the plan.
    var isExtra: Bool
    /// The chosen alarm time; nil until set (tasks without a suggested time).
    var time: Date?
    var isSkipped = false
    /// The suggested time had already passed, so it was moved to shortly from now.
    var timeWasMoved = false
    /// Seconds before Stop Alarm unlocks, when the task sets its own read time.
    var unlockSeconds: Int?
}

/// The check-in rules, kept free of UI so they can be tested.
enum CheckInPlanner {
    /// A task whose time has passed is moved this far ahead, then rounded up to a 5-minute mark.
    static let passedTimeDelay: TimeInterval = 15 * 60

    /// The check-in items for a day's tasks (plan tasks first, then the day's extra tasks).
    static func items(for agenda: DayAgenda, planDefaultReadSeconds: Int?, now: Date,
                      calendar: Calendar = .plan) -> [CheckInItem] {
        agenda.day.tasks.enumerated().map { index, task in
            let isExtra = index >= agenda.planTaskCount
            var item = CheckInItem(id: index, task: task, isExtra: isExtra)
            if let suggested = task.suggestedTime {
                let time = agenda.day.date.date(hour: suggested.hour, minute: suggested.minute, calendar: calendar)
                if time <= now {
                    item.time = movedTime(from: now)
                    item.timeWasMoved = true
                } else {
                    item.time = time
                }
            }
            let defaultRead = isExtra ? Plan.fallbackReadSeconds : (planDefaultReadSeconds ?? Plan.fallbackReadSeconds)
            item.unlockSeconds = task.readSeconds != defaultRead ? task.readSeconds : nil
            return item
        }
    }

    /// Rebuilt items after the plan changed, keeping what the user already chose (time, skip) for tasks
    /// that are still there. Tasks are matched by title.
    static func merge(_ fresh: [CheckInItem], keeping previous: [CheckInItem]) -> [CheckInItem] {
        var unused = previous
        return fresh.map { item in
            guard let index = unused.firstIndex(where: { $0.task.title == item.task.title && $0.isExtra == item.isExtra }) else {
                return item
            }
            let old = unused.remove(at: index)
            var merged = item
            merged.time = old.time
            merged.isSkipped = old.isSkipped
            merged.timeWasMoved = old.timeWasMoved
            return merged
        }
    }

    /// A signature of a day's tasks, used to notice when the plan or extra tasks changed.
    static func signature(of agenda: DayAgenda) -> [String] {
        agenda.day.tasks.enumerated().map { index, task in
            [index >= agenda.planTaskCount ? "extra" : "plan", task.title, task.category,
             task.suggestedTime?.description ?? "-", task.durationMinutes.map { String($0) } ?? "-",
             String(task.readSeconds), task.summary ?? "", String(task.sections.count)].joined(separator: "|")
        } + [agenda.day.dayNote ?? ""]
    }

    /// `now` plus 15 minutes, rounded up to the next 5-minute mark.
    static func movedTime(from now: Date) -> Date {
        roundedUpToFiveMinutes(now.addingTimeInterval(passedTimeDelay))
    }

    /// The starting value when the user taps "Set time": the next full half hour at least 15 minutes away.
    static func defaultNewTime(now: Date) -> Date {
        let t = now.addingTimeInterval(passedTimeDelay).timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (t / 1800).rounded(.up) * 1800)
    }

    /// Every time zone's offset is a multiple of 15 minutes, so 5-minute marks line up with local time.
    static func roundedUpToFiveMinutes(_ date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate.rounded(.down)
        return Date(timeIntervalSinceReferenceDate: (t / 300).rounded(.up) * 300)
    }

    /// For each item that overlaps the next scheduled task (by its duration), the title of that task.
    static func overlaps(in items: [CheckInItem]) -> [Int: String] {
        let timed = items
            .filter { !$0.isSkipped && $0.time != nil }
            .sorted { $0.time! < $1.time! }
        var result: [Int: String] = [:]
        for (current, next) in zip(timed, timed.dropFirst()) {
            guard let minutes = current.task.durationMinutes, let start = current.time, let nextStart = next.time else { continue }
            if start.addingTimeInterval(TimeInterval(minutes * 60)) > nextStart {
                result[current.id] = next.task.title
                result[next.id] = result[next.id] ?? current.task.title
            }
        }
        return result
    }

    /// Why "Lock in my day" isn't possible yet, or nil when it is.
    static func blockingReason(items: [CheckInItem], unansweredCarryOver: Int, now: Date) -> String? {
        if unansweredCarryOver > 0 {
            return "First answer “Did you do these?” for yesterday's tasks."
        }
        if let missing = items.first(where: { !$0.isSkipped && $0.time == nil }) {
            return "Set a time for “\(missing.task.title)”, or skip it today."
        }
        if let passed = items.first(where: { !$0.isSkipped && ($0.time ?? .distantFuture) <= now }) {
            return "“\(passed.task.title)” is set to a time that has already passed."
        }
        return nil
    }
}
