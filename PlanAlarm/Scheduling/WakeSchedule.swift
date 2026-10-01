import Foundation

/// One weekday's wake-up setting. A missing rule means "on, at the default time".
struct WakeDayRule: Codable, Hashable, Sendable {
    var isEnabled = true
    /// Overrides the default wake-up time on this weekday.
    var customTime: TimeOfDay?
}

/// The wake-up alarm: a default time, with optional per-weekday overrides and on/off switches.
struct WakeSchedule: Hashable, Sendable {
    static let standard = WakeSchedule(isEnabled: true, defaultTime: TimeOfDay(hour: 7, minute: 0)!, rules: [:])

    var isEnabled: Bool
    var defaultTime: TimeOfDay
    var rules: [Weekday: WakeDayRule]

    func rule(for weekday: Weekday) -> WakeDayRule {
        rules[weekday] ?? WakeDayRule()
    }

    /// The wake-up time on a weekday, or nil if there's no wake-up alarm that day.
    func time(on weekday: Weekday) -> TimeOfDay? {
        guard isEnabled else { return nil }
        let rule = rule(for: weekday)
        return rule.isEnabled ? (rule.customTime ?? defaultTime) : nil
    }

    /// The next wake-up alarm strictly after `date`, in the calendar's time zone.
    func nextAlarm(after date: Date, calendar: Calendar = .plan) -> Date? {
        let today = LocalDate(date, calendar: calendar)
        for offset in 0...7 {
            let day = today.adding(days: offset)
            guard let time = time(on: day.weekday) else { continue }
            let fire = day.date(hour: time.hour, minute: time.minute, calendar: calendar)
            if fire > date { return fire }
        }
        return nil
    }
}

extension WakeSchedule {
    /// Minutes after the wake-up time at which the wake-up rings sound: at the time, then after gaps of
    /// 9, 7 and 5 minutes, then every 3 minutes, for up to 2 hours (37 rings). The rings stop as soon as
    /// that day's wake-up walk is done.
    static let ringOffsetMinutes: [Int] = [0, 9, 16, 21] + Array(stride(from: 24, through: 120, by: 3))

    /// Rings kept scheduled for the wake-up after the next one (the next one gets all of them, later ones
    /// only their first ring). Every refresh tops them up; this leaves room under iOS's alarm limit for tasks.
    static let secondWakeUpRings = 4
    static let daysAhead = 7

    /// Every wake-up ring on `date`, earliest first, or none if there's no wake-up that day.
    func ringDates(on date: LocalDate, calendar: Calendar = .plan) -> [Date] {
        guard let time = time(on: date.weekday) else { return [] }
        let wake = date.date(hour: time.hour, minute: time.minute, calendar: calendar)
        return Self.ringOffsetMinutes.map { wake.addingTimeInterval(TimeInterval($0 * 60)) }
    }

    /// The wake-up rings to keep scheduled, per date ("YYYY-MM-DD"): future rings only, none for days whose
    /// wake-up walk is done. The next wake-up gets its whole chain, the one after its first few rings, and
    /// the rest of the week one ring each. Yesterday is included because a late wake-up can run past midnight.
    func plannedRings(now: Date, awake: Set<String>, calendar: Calendar = .plan) -> [String: [Date]] {
        let today = LocalDate(now, calendar: calendar)
        var result: [String: [Date]] = [:]
        var position = 0
        for offset in -1...Self.daysAhead {
            let day = today.adding(days: offset)
            guard !awake.contains(day.description) else { continue }
            let all = ringDates(on: day, calendar: calendar)
            let kept: [Date]
            switch position {
            case 0: kept = all
            case 1: kept = Array(all.prefix(Self.secondWakeUpRings))
            default: kept = Array(all.prefix(1))
            }
            let future = kept.filter { $0 > now }
            guard !future.isEmpty else { continue }
            result[day.description] = future
            position += 1
        }
        return result
    }

    /// The day whose wake-up walk is due: its first ring has gone off, the walk isn't done, and its last
    /// ring was less than 30 minutes ago.
    func pendingWakeUp(now: Date, awake: Set<String>, calendar: Calendar = .plan) -> LocalDate? {
        let today = LocalDate(now, calendar: calendar)
        for day in [today, today.adding(days: -1)] where !awake.contains(day.description) {
            let rings = ringDates(on: day, calendar: calendar)
            guard let first = rings.first, let last = rings.last else { continue }
            if first <= now && now <= last.addingTimeInterval(30 * 60) {
                return day
            }
        }
        return nil
    }

    /// The next wake-up still to ring, skipping days whose walk is already done.
    func nextWakeUp(after now: Date, awake: Set<String>, calendar: Calendar = .plan) -> (day: LocalDate, date: Date)? {
        let today = LocalDate(now, calendar: calendar)
        for offset in 0...Self.daysAhead {
            let day = today.adding(days: offset)
            guard !awake.contains(day.description),
                  let first = ringDates(on: day, calendar: calendar).first, first > now else { continue }
            return (day, first)
        }
        return nil
    }
}

extension Weekday {
    /// All weekdays starting from the calendar's first day of the week.
    static func ordered(firstWeekday: Int = Calendar.plan.firstWeekday) -> [Weekday] {
        let sundayFirst: [Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        let start = (firstWeekday - 1 + 7) % 7
        return Array(sundayFirst[start...] + sundayFirst[..<start])
    }
}
