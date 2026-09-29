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

    private func entry(_ key: String, first: Date, rings: [Date] = []) -> PendingTaskAlarm {
        PendingTaskAlarm(key: key, task: task, firstAlarmAt: first,
                         rings: rings.map { ScheduledRing(id: UUID(), date: $0) })
    }

    @Test func roundTripsThroughUserDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "AlarmRegistryTests-\(UUID().uuidString)"))
        var registry = AlarmRegistry()
        registry.wakeAlarmIDs = [UUID()]
        registry.testAlarmIDs = [UUID()]
        var saved = entry("2026-10-05#1", first: .now, rings: [.now, .now.addingTimeInterval(300)])
        saved.unlockSeconds = 45
        registry.upsert(saved)
        registry.save(to: defaults)

        let loaded = AlarmRegistry.load(from: defaults)
        #expect(loaded.wakeAlarmIDs == registry.wakeAlarmIDs)
        #expect(loaded.tasks == registry.tasks)
        #expect(loaded.task(forKey: "2026-10-05#1")?.task == task)
        #expect(loaded.task(forKey: "2026-10-05#1")?.unlockSeconds == 45)
        #expect(loaded.knownAlarmIDs.count == 4)
    }

    @Test func upsertReplacesAndRemoveDeletes() {
        var registry = AlarmRegistry()
        var item = entry("k", first: .now)
        registry.upsert(item)
        item.snoozeCount = 3
        registry.upsert(item)
        #expect(registry.tasks.count == 1)
        #expect(registry.task(forKey: "k")?.snoozeCount == 3)
        registry.removeTask(forKey: "k")
        #expect(registry.tasks.isEmpty)
    }

    @Test func pendingAcknowledgementStartsAtTheFirstAlarm() {
        #expect(!entry("a", first: .now.addingTimeInterval(600)).isPendingAcknowledgement())
        #expect(entry("b", first: .now.addingTimeInterval(-60)).isPendingAcknowledgement())
    }

    @Test func chainRingsFollowTheSnoozeLength() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let dates = AlarmRegistry.chainDates(startingAt: start, interval: 7 * 60, count: 4)
        #expect(dates == [0, 7, 14, 21].map { start.addingTimeInterval(TimeInterval($0 * 60)) })
    }

    @Test func chainsCoverAboutAnHour() {
        #expect(AlarmRegistry.chainLength(snoozeInterval: 5 * 60) == 12)   // capped at 12 rings
        #expect(AlarmRegistry.chainLength(snoozeInterval: 10 * 60) == 7)   // 0, 10 … 60 min
        #expect(AlarmRegistry.chainLength(snoozeInterval: 30 * 60) == 3)   // 0, 30, 60 min
        #expect(AlarmRegistry.chainLength(snoozeInterval: 1 * 60) == 12)
    }

    @Test func nextRingSkipsPastOnes() {
        let item = entry("k", first: .now.addingTimeInterval(-600),
                         rings: [.now.addingTimeInterval(-600), .now.addingTimeInterval(-300), .now.addingTimeInterval(300)])
        #expect(item.nextRing()?.date == item.rings[2].date)
    }
}

@MainActor
struct DayAgendaTests {
    private let date = Fixtures.date

    private func extra(_ title: String, on iso: String, createdAt offset: TimeInterval) -> ExtraTask {
        let task = PlanTask(taskRef: nil, title: title, category: "other", summary: nil, sections: [],
                            durationMinutes: nil, readSeconds: 30, suggestedTime: nil)
        let item = ExtraTask(date: date(iso), task: task)
        item.createdAt = Date(timeIntervalSince1970: 1_800_000_000 + offset)
        return item
    }

    @Test func extraTasksFollowThePlanTasks() throws {
        let plan = try #require(PlanParser.parse(text: Fixtures.briefExample).plan)
        let extras = [extra("Second", on: "2026-10-05", createdAt: 2), extra("First", on: "2026-10-05", createdAt: 1),
                      extra("Other day", on: "2026-10-06", createdAt: 0)]
        let agenda = DayAgenda(date: date("2026-10-05"), plan: plan, extras: extras)
        #expect(agenda.planTaskCount == 2)
        #expect(agenda.day.tasks.map(\.title) == ["Morning stretches", "Gym — Push day", "First", "Second"])
        #expect(agenda.extra(at: 1) == nil)
        #expect(agenda.extra(at: 2)?.task?.title == "First")
        #expect(agenda.extra(at: 4) == nil)
    }

    @Test func extraTasksWorkOutsideThePlanAndWithoutOne() throws {
        let plan = try #require(PlanParser.parse(text: Fixtures.briefExample).plan)
        let extras = [extra("Before the plan", on: "2026-09-29", createdAt: 0)]
        let outside = DayAgenda(date: date("2026-09-29"), plan: plan, extras: extras)
        #expect(!outside.day.isInPlan)
        #expect(outside.day.tasks.map(\.title) == ["Before the plan"])

        let noPlan = DayAgenda(date: date("2026-09-29"), plan: nil, extras: extras)
        #expect(noPlan.planTaskCount == 0)
        #expect(noPlan.day.tasks.map(\.title) == ["Before the plan"])
    }
}
