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

    /// Weekdays grouped by wake-up time. Each group becomes one repeating AlarmKit alarm.
    var alarmGroups: [WakeAlarmGroup] {
        var byTime: [TimeOfDay: [Weekday]] = [:]
        for weekday in Weekday.allCases {
            if let time = time(on: weekday) {
                byTime[time, default: []].append(weekday)
            }
        }
        return byTime.map { WakeAlarmGroup(time: $0.key, weekdays: $0.value) }.sorted { $0.time < $1.time }
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

struct WakeAlarmGroup: Hashable, Sendable {
    var time: TimeOfDay
    var weekdays: [Weekday]
}

extension Weekday {
    var localeWeekday: Locale.Weekday {
        switch self {
        case .monday: .monday
        case .tuesday: .tuesday
        case .wednesday: .wednesday
        case .thursday: .thursday
        case .friday: .friday
        case .saturday: .saturday
        case .sunday: .sunday
        }
    }

    /// All weekdays starting from the calendar's first day of the week.
    static func ordered(firstWeekday: Int = Calendar.plan.firstWeekday) -> [Weekday] {
        let sundayFirst: [Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        let start = (firstWeekday - 1 + 7) % 7
        return Array(sundayFirst[start...] + sundayFirst[..<start])
    }
}
