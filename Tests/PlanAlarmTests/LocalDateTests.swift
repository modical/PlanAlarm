import Foundation
import Testing
@testable import PlanAlarm

struct LocalDateTests {
    private let date = Fixtures.date

    @Test func parsesStrictISODates() {
        #expect(LocalDate(isoString: "2026-10-06") == LocalDate(year: 2026, month: 10, day: 6))
        #expect(LocalDate(isoString: "2028-02-29") != nil)
        for bad in ["2026-02-29", "2026-13-01", "2026-00-10", "2026-04-31", "2026-1-5", "26-10-06",
                    "2026/10/06", "2026-10-06T00:00", "", "abcd-ef-gh", " 2026-10-06"] {
            #expect(LocalDate(isoString: bad) == nil, "\(bad)")
        }
        #expect(date("2026-01-05").description == "2026-01-05")
    }

    @Test func weekdays() {
        #expect(date("1970-01-01").weekday == .thursday)
        #expect(date("1969-12-31").weekday == .wednesday)
        #expect(date("2000-02-29").weekday == .tuesday)
        #expect(date("2024-12-31").weekday == .tuesday)
        #expect(date("2026-10-01").weekday == .thursday)
        #expect(date("2026-10-05").weekday == .monday)
        #expect(date("2026-10-10").weekday == .saturday)
        #expect(Weekday.sunday.calendarWeekday == 1)
        #expect(Weekday.monday.calendarWeekday == 2)
        #expect(Weekday.saturday.calendarWeekday == 7)
    }

    @Test func dayArithmeticCrossesMonthsAndYears() {
        #expect(date("2026-10-31").adding(days: 1) == date("2026-11-01"))
        #expect(date("2026-12-31").adding(days: 1) == date("2027-01-01"))
        #expect(date("2028-02-28").adding(days: 1) == date("2028-02-29"))
        #expect(date("2026-03-01").adding(days: -1) == date("2026-02-28"))
        #expect(date("2026-10-01").days(until: date("2026-10-31")) == 30)
        for day in stride(from: -800_000, through: 800_000, by: 997) {
            #expect(LocalDate(daysSinceEpoch: day).daysSinceEpoch == day)
        }
    }

    @Test func matchesFoundationCalendar() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        let epoch = Date(timeIntervalSince1970: 0)
        for day in stride(from: 0, through: 40_000, by: 373) {
            let foundationDate = try #require(utc.date(byAdding: .day, value: day, to: epoch))
            #expect(LocalDate(foundationDate, calendar: utc) == LocalDate(daysSinceEpoch: day))
        }
    }

    @Test func startOfWeekRespectsFirstWeekday() {
        let thursday = date("2026-10-08")
        #expect(thursday.startOfWeek(firstWeekday: 2) == date("2026-10-05")) // Monday
        #expect(thursday.startOfWeek(firstWeekday: 1) == date("2026-10-04")) // Sunday
        #expect(thursday.startOfWeek(firstWeekday: 7) == date("2026-10-03")) // Saturday
        #expect(date("2026-10-05").startOfWeek(firstWeekday: 2) == date("2026-10-05"))
    }

    /// Egypt's DST starts at midnight on the last Friday of April (that day has 23 hours)
    /// and ends at midnight after the last Thursday of October (that day has 25 hours).
    @Test func cairoDSTDaysConvertCleanly() throws {
        var cairo = Calendar(identifier: .gregorian)
        cairo.timeZone = try #require(TimeZone(identifier: "Africa/Cairo"))
        let springForward = date("2026-04-24")
        let fallBack = date("2026-10-29")

        for transition in [springForward, fallBack] {
            for offset in -1...1 {
                let day = transition.adding(days: offset)
                #expect(LocalDate(day.date(calendar: cairo), calendar: cairo) == day)
                #expect(LocalDate(day.date(hour: 0, calendar: cairo), calendar: cairo) == day)
                #expect(LocalDate(day.date(hour: 23, minute: 59, calendar: cairo), calendar: cairo) == day)
            }
        }
        let springLength = try #require(cairo.dateInterval(of: .day, for: springForward.date(calendar: cairo))?.duration)
        let fallLength = try #require(cairo.dateInterval(of: .day, for: fallBack.date(calendar: cairo))?.duration)
        // Foundation's interval math isn't exact to the last bit, so compare to within a second.
        #expect(abs(springLength - 23 * 3600) < 1, "\(springLength)")
        #expect(abs(fallLength - 25 * 3600) < 1, "\(fallLength)")
    }

    @Test func timeOfDayParsing() {
        #expect(TimeOfDay(string: "00:00") == TimeOfDay(hour: 0, minute: 0))
        #expect(TimeOfDay(string: "07:30")?.minutesSinceMidnight == 450)
        #expect(TimeOfDay(string: "23:59")?.description == "23:59")
        for bad in ["24:00", "25:00", "7:30", "12:60", "ab:cd", "12-30", "12:3", "", "07:30 "] {
            #expect(TimeOfDay(string: bad) == nil, "\(bad)")
        }
        #expect(TimeOfDay(hour: 7, minute: 5)!.description == "07:05")
        #expect(TimeOfDay(hour: 7, minute: 5)! < TimeOfDay(hour: 18, minute: 0)!)
    }
}
