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
        for weekday in Weekday.allCases {
            #expect(WakeSchedule.standard.time(on: weekday) == time("07:00"))
        }
    }

    @Test func singleDaysCanChangeOrSwitchOff() {
        #expect(customized.time(on: .monday) == time("07:00"))
        #expect(customized.time(on: .saturday) == time("09:00"))
        #expect(customized.time(on: .friday) == nil)
    }

    @Test func disabledMeansNoAlarms() throws {
        var schedule = customized
        schedule.isEnabled = false
        #expect(schedule.nextAlarm(after: .now) == nil)
        #expect(schedule.plannedRings(now: try cairoDate("2026-10-05", 6), awake: [], calendar: try cairo()).isEmpty)
    }

    // MARK: Wake-up rings

    @Test func ringsGetCloserTogetherForTwoHours() {
        let offsets = WakeSchedule.ringOffsetMinutes
        #expect(offsets.prefix(6) == [0, 9, 16, 21, 24, 27])
        #expect(offsets.last == 120)
        #expect(offsets.count == 37)
        #expect(zip(offsets, offsets.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test func ringDatesStartAtTheWakeUpTime() throws {
        let calendar = try cairo()
        let rings = WakeSchedule.standard.ringDates(on: Fixtures.date("2026-10-05"), calendar: calendar)
        #expect(rings.first == (try cairoDate("2026-10-05", 7)))
        #expect(rings[1] == (try cairoDate("2026-10-05", 7, 9)))
        #expect(rings.last == (try cairoDate("2026-10-05", 9)))
        #expect(customized.ringDates(on: Fixtures.date("2026-10-09"), calendar: calendar).isEmpty) // Friday off
    }

    @Test func nextWakeUpGetsTheWholeChainLaterOnesFewer() throws {
        let calendar = try cairo()
        let planned = customized.plannedRings(now: try cairoDate("2026-10-05", 6), awake: [], calendar: calendar)
        #expect(planned["2026-10-05"]?.count == 37)
        #expect(planned["2026-10-06"]?.count == WakeSchedule.secondWakeUpRings)
        #expect(planned["2026-10-07"]?.count == 1)
        #expect(planned["2026-10-09"] == nil)                                   // Friday off
        let saturdayNine = try cairoDate("2026-10-10", 9)
        #expect(planned["2026-10-10"] == [saturdayNine])                        // Saturday at 9
        #expect(planned.keys.sorted() == ["2026-10-05", "2026-10-06", "2026-10-07", "2026-10-08",
                                          "2026-10-10", "2026-10-11", "2026-10-12"])
    }

    @Test func ringingDayKeepsOnlyItsFutureRings() throws {
        let calendar = try cairo()
        let now = try cairoDate("2026-10-05", 7, 10)
        let planned = WakeSchedule.standard.plannedRings(now: now, awake: [], calendar: calendar)
        let today = try #require(planned["2026-10-05"])
        #expect(today.count == 35)
        #expect(today.first == (try cairoDate("2026-10-05", 7, 16)))
        #expect(today.allSatisfy { $0 > now })
        #expect(planned["2026-10-06"]?.count == WakeSchedule.secondWakeUpRings)
    }

    @Test func walkingStopsTodayAndMovesTheChainOn() throws {
        let calendar = try cairo()
        let planned = WakeSchedule.standard.plannedRings(now: try cairoDate("2026-10-05", 7, 10), awake: ["2026-10-05"],
                                                         calendar: calendar)
        #expect(planned["2026-10-05"] == nil)
        #expect(planned["2026-10-06"]?.count == 37)
        #expect(planned["2026-10-07"]?.count == WakeSchedule.secondWakeUpRings)
    }

    @Test func lateWakeUpRunsPastMidnight() throws {
        let calendar = try cairo()
        var schedule = WakeSchedule.standard
        schedule.defaultTime = time("23:30")
        let now = try cairoDate("2026-10-06", 0, 30)
        let planned = schedule.plannedRings(now: now, awake: [], calendar: calendar)
        #expect(planned["2026-10-05"]?.count == 20)                             // 00:33 … 01:30 after 23:30
        #expect(planned["2026-10-06"]?.count == WakeSchedule.secondWakeUpRings)
        #expect(schedule.pendingWakeUp(now: now, awake: [], calendar: calendar) == Fixtures.date("2026-10-05"))
    }

    @Test func walkIsDueFromTheFirstRingUntilHalfAnHourAfterTheLast() throws {
        let calendar = try cairo()
        let monday = Fixtures.date("2026-10-05")
        let schedule = WakeSchedule.standard
        #expect(schedule.pendingWakeUp(now: try cairoDate("2026-10-05", 6, 59), awake: [], calendar: calendar) == nil)
        #expect(schedule.pendingWakeUp(now: try cairoDate("2026-10-05", 7), awake: [], calendar: calendar) == monday)
        #expect(schedule.pendingWakeUp(now: try cairoDate("2026-10-05", 9, 29), awake: [], calendar: calendar) == monday)
        #expect(schedule.pendingWakeUp(now: try cairoDate("2026-10-05", 9, 31), awake: [], calendar: calendar) == nil)
        #expect(schedule.pendingWakeUp(now: try cairoDate("2026-10-05", 8), awake: ["2026-10-05"], calendar: calendar) == nil)
    }

    @Test func nextWakeUpSkipsDaysAlreadyUp() throws {
        let calendar = try cairo()
        let early = try cairoDate("2026-10-05", 6)
        #expect(WakeSchedule.standard.nextWakeUp(after: early, awake: [], calendar: calendar)?.date == (try cairoDate("2026-10-05", 7)))
        #expect(WakeSchedule.standard.nextWakeUp(after: early, awake: ["2026-10-05"], calendar: calendar)?.date
                == (try cairoDate("2026-10-06", 7)))
        // Thursday after 7 → Friday off → Saturday at 9.
        let next = customized.nextWakeUp(after: try cairoDate("2026-10-08", 8), awake: [], calendar: calendar)
        #expect(next?.day == Fixtures.date("2026-10-10"))
        #expect(next?.date == (try cairoDate("2026-10-10", 9)))
    }

    @Test func wakeUpRingsAcrossCairoDSTEnd() throws {
        let calendar = try cairo()
        // Clocks go back at the end of Thursday 29 Oct 2026 (a 25-hour day).
        let rings = WakeSchedule.standard.ringDates(on: Fixtures.date("2026-10-30"), calendar: calendar)
        let first = calendar.dateComponents([.day, .hour, .minute], from: try #require(rings.first))
        #expect(first.day == 30)
        #expect(first.hour == 7)
        #expect(first.minute == 0)
        let last = calendar.dateComponents([.hour, .minute], from: try #require(rings.last))
        #expect(last.hour == 9)
        #expect(last.minute == 0)
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

    @Test func wakeChainsAndAwakeDaysAreSaved() throws {
        let defaults = try #require(UserDefaults(suiteName: "AlarmRegistryTests-\(UUID().uuidString)"))
        var registry = AlarmRegistry()
        let ring = ScheduledRing(id: UUID(), date: Date(timeIntervalSince1970: 1_800_000_000))
        registry.wakeChains["2026-10-05"] = [ring]
        registry.markAwake("2026-10-04")
        registry.save(to: defaults)

        let loaded = AlarmRegistry.load(from: defaults)
        #expect(loaded.wakeChains["2026-10-05"] == [ring])
        #expect(loaded.awakeDates == ["2026-10-04"])
        #expect(loaded.knownAlarmIDs.contains(ring.id))
    }

    @Test func awakeDaysKeepTheLatestFortnight() {
        var registry = AlarmRegistry()
        for day in 1...20 {
            registry.markAwake(Fixtures.date("2026-10-01").adding(days: day).description)
        }
        registry.markAwake("2026-10-21")  // already there
        #expect(registry.awakeDates.count == 14)
        #expect(registry.awakeDates.first == "2026-10-08")
        #expect(registry.awakeDates.last == "2026-10-21")
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
