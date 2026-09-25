import Foundation
import Testing
@testable import PlanAlarm

struct WakeScheduleTests {
    private func time(_ text: String) -> TimeOfDay { TimeOfDay(string: text)! }

    private func cairo() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Africa/Cairo"))
        return calendar
    }

    private func cairoDate(_ iso: String, _ hour: Int, _ minute: Int = 0) throws -> Date {
        Fixtures.date(iso).date(hour: hour, minute: minute, calendar: try cairo())
    }

    private var customized: WakeSchedule {
        var schedule = WakeSchedule.standard
        schedule.rules[.friday] = WakeDayRule(isEnabled: false)
        schedule.rules[.saturday] = WakeDayRule(isEnabled: true, customTime: time("09:00"))
        return schedule
    }

    @Test func defaultIsSevenEveryDay() {
        let groups = WakeSchedule.standard.alarmGroups
        #expect(groups.count == 1)
        #expect(groups.first?.time == time("07:00"))
        #expect(groups.first?.weekdays == Weekday.allCases)
    }

    @Test func weekdaysAreGroupedByTime() {
        let groups = customized.alarmGroups
        #expect(groups.map(\.time) == [time("07:00"), time("09:00")])
        #expect(groups[0].weekdays == [.monday, .tuesday, .wednesday, .thursday, .sunday])
        #expect(groups[1].weekdays == [.saturday])
        #expect(customized.time(on: .friday) == nil)
    }

    @Test func disabledMeansNoAlarms() {
        var schedule = customized
        schedule.isEnabled = false
        #expect(schedule.alarmGroups.isEmpty)
        #expect(schedule.nextAlarm(after: .now) == nil)
    }

    @Test func nextAlarmSkipsDaysOff() throws {
        let calendar = try cairo()
        #expect(customized.nextAlarm(after: try cairoDate("2026-10-05", 6), calendar: calendar) == (try cairoDate("2026-10-05", 7)))
        // Exactly at the alarm time, the next one is tomorrow.
        #expect(customized.nextAlarm(after: try cairoDate("2026-10-05", 7), calendar: calendar) == (try cairoDate("2026-10-06", 7)))
        // Thursday morning after 7 → Friday is off → Saturday at 9.
        #expect(customized.nextAlarm(after: try cairoDate("2026-10-08", 8), calendar: calendar) == (try cairoDate("2026-10-10", 9)))
    }

    @Test func nextAlarmAcrossCairoDSTEnd() throws {
        let calendar = try cairo()
        // Clocks go back at the end of Thursday 29 Oct 2026; the next wake-up is still 07:00 local.
        let next = try #require(WakeSchedule.standard.nextAlarm(after: try cairoDate("2026-10-29", 23, 30), calendar: calendar))
        let parts = calendar.dateComponents([.day, .hour, .minute], from: next)
        #expect(parts.day == 30)
        #expect(parts.hour == 7)
        #expect(parts.minute == 0)
    }

    @Test func weekdaysFollowTheLocaleFirstDay() {
        #expect(Weekday.ordered(firstWeekday: 2).first == .monday)
        #expect(Weekday.ordered(firstWeekday: 7).first == .saturday)
        #expect(Weekday.ordered(firstWeekday: 1) == [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday])
    }

    @Test func settingsStoreTheSchedule() {
        let settings = AppSettings()
        #expect(settings.wakeSchedule == .standard)
        settings.wakeSchedule = customized
        #expect(settings.wakeSchedule == customized)
        #expect(settings.wakeHour == 7)
    }
}

struct AlarmRegistryTests {
    private let task = PlanTask(taskRef: "push-day", title: "Gym — Push day", category: "gym", summary: "Chest.",
                                sections: [TaskSection(title: "Main", items: ["Bench press"])],
                                durationMinutes: 75, readSeconds: 60, suggestedTime: TimeOfDay(hour: 18, minute: 0))

    @Test func roundTripsThroughUserDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "AlarmRegistryTests-\(UUID().uuidString)"))
        var registry = AlarmRegistry()
        registry.wakeAlarmIDs = [UUID()]
        registry.upsert(PendingTaskAlarm(key: "2026-10-05#1", task: task, firstAlarmAt: .now, alarmID: UUID(), nextAlarmAt: .now))
        registry.save(to: defaults)

        let loaded = AlarmRegistry.load(from: defaults)
        #expect(loaded.wakeAlarmIDs == registry.wakeAlarmIDs)
        #expect(loaded.tasks == registry.tasks)
        #expect(loaded.task(forKey: "2026-10-05#1")?.task == task)
    }

    @Test func upsertReplacesAndRemoveDeletes() {
        var registry = AlarmRegistry()
        var entry = PendingTaskAlarm(key: "k", task: task, firstAlarmAt: .now, alarmID: UUID(), nextAlarmAt: .now)
        registry.upsert(entry)
        entry.snoozeCount = 3
        registry.upsert(entry)
        #expect(registry.tasks.count == 1)
        #expect(registry.task(forKey: "k")?.snoozeCount == 3)
        registry.removeTask(forKey: "k")
        #expect(registry.tasks.isEmpty)
    }

    @Test func pendingAcknowledgementStartsAtTheFirstAlarm() {
        let later = PendingTaskAlarm(key: "a", task: task, firstAlarmAt: .now.addingTimeInterval(600), alarmID: UUID(), nextAlarmAt: .now)
        let earlier = PendingTaskAlarm(key: "b", task: task, firstAlarmAt: .now.addingTimeInterval(-60), alarmID: UUID(), nextAlarmAt: .now)
        #expect(!later.isPendingAcknowledgement())
        #expect(earlier.isPendingAcknowledgement())
    }
}
