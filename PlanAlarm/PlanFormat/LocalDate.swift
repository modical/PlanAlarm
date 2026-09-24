import Foundation

extension Calendar {
    /// Gregorian calendar in the device's current time zone.
    /// Plan dates are always Gregorian, even if the phone is set to another calendar system.
    static var plan: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.locale = .current
        calendar.firstWeekday = Calendar.current.firstWeekday
        return calendar
    }
}

/// A calendar day with no time or time zone, e.g. "2026-10-06".
///
/// Day arithmetic is pure Gregorian math, so it never depends on time zones or DST.
/// Converting to and from `Date` goes through `Calendar.plan` (the device's time zone).
struct LocalDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month),
              (1...Self.daysInMonth(year: year, month: month)).contains(day) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses a strict "YYYY-MM-DD" string.
    init?(isoString: String) {
        let parts = isoString.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCIIDigit) }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// The day that contains `date` in the calendar's time zone.
    init(_ date: Date, calendar: Calendar = .plan) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(unchecked: parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    private init(unchecked year: Int, _ month: Int, _ day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    static func today(calendar: Calendar = .plan) -> LocalDate {
        LocalDate(.now, calendar: calendar)
    }

    var description: String {
        "\(Self.pad(year, 4))-\(Self.pad(month, 2))-\(Self.pad(day, 2))"
    }

    static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    // MARK: Day arithmetic

    /// Days since 1970-01-01 (proleptic Gregorian; Howard Hinnant's days_from_civil).
    var daysSinceEpoch: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let shiftedMonth = (month + 9) % 12 // March = 0
        let dayOfYear = (153 * shiftedMonth + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    init(daysSinceEpoch: Int) {
        let z = daysSinceEpoch + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shiftedMonth = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
        let month = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        self.init(unchecked: year, month, day)
    }

    func adding(days: Int) -> LocalDate {
        LocalDate(daysSinceEpoch: daysSinceEpoch + days)
    }

    func days(until other: LocalDate) -> Int {
        other.daysSinceEpoch - daysSinceEpoch
    }

    var weekday: Weekday {
        // 1970-01-01 was a Thursday (index 3 in Monday-first order).
        Weekday.allCases[((daysSinceEpoch % 7) + 7 + 3) % 7]
    }

    /// The first day of the week containing this date. `firstWeekday` uses `Calendar` numbering (1 = Sunday).
    func startOfWeek(firstWeekday: Int) -> LocalDate {
        adding(days: -((weekday.calendarWeekday - firstWeekday + 7) % 7))
    }

    // MARK: Converting to Date

    /// This day at a local time. Defaults to noon, which exists on every day (Cairo's DST switches at midnight).
    func date(hour: Int = 12, minute: Int = 0, calendar: Calendar = .plan) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))
            ?? Date(timeIntervalSince1970: TimeInterval(daysSinceEpoch) * 86_400)
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
}

/// A local wall-clock time, "HH:mm" in 24-hour format.
struct TimeOfDay: Hashable, Comparable, Sendable, CustomStringConvertible {
    let hour: Int
    let minute: Int

    init?(hour: Int, minute: Int) {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        self.hour = hour
        self.minute = minute
    }

    /// Parses a strict "HH:mm" string (two digits each, 24-hour).
    init?(string: String) {
        let chars = Array(string)
        guard chars.count == 5, chars[2] == ":",
              [chars[0], chars[1], chars[3], chars[4]].allSatisfy(\.isASCIIDigit),
              let hour = Int(String(chars[0...1])), let minute = Int(String(chars[3...4]))
        else { return nil }
        self.init(hour: hour, minute: minute)
    }

    var minutesSinceMidnight: Int { hour * 60 + minute }

    var description: String {
        (hour < 10 ? "0" : "") + String(hour) + ":" + (minute < 10 ? "0" : "") + String(minute)
    }

    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }
}

/// Days of the week, in the order used by the plan file (Monday first).
enum Weekday: String, CaseIterable, Sendable {
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday

    var displayName: String { rawValue.capitalized }

    /// `Calendar` weekday number (1 = Sunday … 7 = Saturday).
    var calendarWeekday: Int {
        self == .sunday ? 1 : Weekday.allCases.firstIndex(of: self)! + 2
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
