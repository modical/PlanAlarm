import Foundation
import SwiftData
import Testing
@testable import PlanAlarm

@MainActor
struct CheckInPlannerTests {
    private let date = Fixtures.date

    private func cairo() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Africa/Cairo"))
        return calendar
    }

    private func at(_ iso: String, _ hour: Int, _ minute: Int, _ second: Int = 0) throws -> Date {
        let calendar = try cairo()
        return Fixtures.date(iso).date(hour: hour, minute: minute, calendar: calendar).addingTimeInterval(TimeInterval(second))
    }

    private func briefPlan() throws -> Plan {
        try #require(PlanParser.parse(text: Fixtures.briefExample).plan)
    }

    private func task(_ title: String, duration: Int? = nil) -> PlanTask {
        PlanTask(taskRef: nil, title: title, category: "other", summary: nil, sections: [],
                 durationMinutes: duration, readSeconds: 30, suggestedTime: nil)
    }

    @Test func passedTimesMoveToFifteenMinutesFromNow() throws {
        let plan = try briefPlan()
        let agenda = DayAgenda(date: date("2026-10-05"), plan: plan, extras: [])
        let items = CheckInPlanner.items(for: agenda, planDefaultReadSeconds: plan.defaultReadSeconds,
                                         now: try at("2026-10-05", 9, 2, 30), calendar: try cairo())
        #expect(items.map(\.task.title) == ["Morning stretches", "Gym — Push day"])
        #expect(items[0].timeWasMoved)
        #expect(items[0].time == (try at("2026-10-05", 9, 20)))
        #expect(!items[1].timeWasMoved)
        #expect(items[1].time == (try at("2026-10-05", 18, 0)))
    }

    @Test func unlockSecondsOnlyWhenTheTaskSetsItsOwn() throws {
        let plan = try briefPlan()
        let agenda = DayAgenda(date: date("2026-10-05"), plan: plan, extras: [])
        let items = CheckInPlanner.items(for: agenda, planDefaultReadSeconds: plan.defaultReadSeconds,
                                         now: try at("2026-10-05", 6, 0), calendar: try cairo())
        #expect(items[0].unlockSeconds == nil) // stretches use the plan default → Settings value
        #expect(items[1].unlockSeconds == 60)  // push day sets 60 s
    }

    @Test func extraTasksWithoutATimeNeedOne() throws {
        let extra = ExtraTask(date: date("2026-09-30"), task: task("Call the bank"))
        let agenda = DayAgenda(date: date("2026-09-30"), plan: nil, extras: [extra])
        let items = CheckInPlanner.items(for: agenda, planDefaultReadSeconds: nil, now: try at("2026-09-30", 8, 0), calendar: try cairo())
        #expect(items.count == 1)
        #expect(items[0].isExtra)
        #expect(items[0].time == nil)
        #expect(CheckInPlanner.blockingReason(items: items, unansweredCarryOver: 0, now: try at("2026-09-30", 8, 0))
                == "Set a time for “Call the bank”, or skip it today.")
    }

    @Test func rounding() throws {
        #expect(CheckInPlanner.movedTime(from: try at("2026-10-05", 9, 0)) == (try at("2026-10-05", 9, 15)))
        #expect(CheckInPlanner.movedTime(from: try at("2026-10-05", 9, 2, 30)) == (try at("2026-10-05", 9, 20)))
        #expect(CheckInPlanner.movedTime(from: try at("2026-10-05", 23, 50)) == (try at("2026-10-06", 0, 5)))
        #expect(CheckInPlanner.defaultNewTime(now: try at("2026-10-05", 9, 0)) == (try at("2026-10-05", 9, 30)))
        #expect(CheckInPlanner.defaultNewTime(now: try at("2026-10-05", 9, 20)) == (try at("2026-10-05", 10, 0)))
    }

    @Test func overlapsUseDurations() throws {
        let items = [
            CheckInItem(id: 0, task: task("Gym", duration: 60), isExtra: false, time: try at("2026-10-05", 9, 0)),
            CheckInItem(id: 1, task: task("Study", duration: 30), isExtra: false, time: try at("2026-10-05", 9, 30)),
            CheckInItem(id: 2, task: task("Lunch", duration: 30), isExtra: false, time: try at("2026-10-05", 12, 0)),
            CheckInItem(id: 3, task: task("No duration"), isExtra: false, time: try at("2026-10-05", 11, 0)),
        ]
        let overlaps = CheckInPlanner.overlaps(in: items)
        #expect(overlaps[0] == "Study")
        #expect(overlaps[1] == "Gym")
        #expect(overlaps[2] == nil)
        #expect(overlaps[3] == nil)

        var skipped = items
        skipped[1].isSkipped = true
        #expect(CheckInPlanner.overlaps(in: skipped).isEmpty)
    }

    @Test func blockingReasons() throws {
        let now = try at("2026-10-05", 10, 0)
        var item = CheckInItem(id: 0, task: task("Gym"), isExtra: false, time: try at("2026-10-05", 18, 0))
        #expect(CheckInPlanner.blockingReason(items: [item], unansweredCarryOver: 1, now: now)?.hasPrefix("First answer") == true)
        #expect(CheckInPlanner.blockingReason(items: [item], unansweredCarryOver: 0, now: now) == nil)
        item.time = try at("2026-10-05", 9, 0)
        #expect(CheckInPlanner.blockingReason(items: [item], unansweredCarryOver: 0, now: now)?.contains("already passed") == true)
        item.isSkipped = true
        #expect(CheckInPlanner.blockingReason(items: [item], unansweredCarryOver: 0, now: now) == nil)
        #expect(CheckInPlanner.blockingReason(items: [], unansweredCarryOver: 0, now: now) == nil)
    }

    @Test func checkInReminderTimes() throws {
        let calendar = try cairo()
        let dates = WakeSchedule.standard.checkInReminderDates(on: date("2026-10-05"), interval: 30 * 60, count: 4, calendar: calendar)
        #expect(try dates == [at("2026-10-05", 7, 30), at("2026-10-05", 8, 0), at("2026-10-05", 8, 30), at("2026-10-05", 9, 0)])

        var noFridays = WakeSchedule.standard
        noFridays.rules[.friday] = WakeDayRule(isEnabled: false)
        #expect(noFridays.checkInReminderDates(on: date("2026-10-09"), interval: 1800, count: 4, calendar: calendar).isEmpty)
    }
}

@MainActor
struct DayStoreTests {
    private let date = Fixtures.date

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(for: DayRecord.self, TaskRecord.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func item(_ id: Int, _ title: String, time: Date?, skipped: Bool = false) -> CheckInItem {
        let task = PlanTask(taskRef: nil, title: title, category: "gym", summary: nil, sections: [],
                            durationMinutes: 30, readSeconds: 30, suggestedTime: nil)
        return CheckInItem(id: id, task: task, isExtra: false, time: time, isSkipped: skipped)
    }

    @Test func lockInCreatesTheDay() throws {
        let context = try makeContext()
        let day = date("2026-10-05")
        #expect(!DayStore.isLockedIn(day, in: context))
        let time = day.date(hour: 18, minute: 0)
        let records = try DayStore.lockIn(date: day, dayNote: "Push day.", planName: "October Cut",
                                          items: [item(0, "Gym", time: time), item(1, "Walk", time: nil, skipped: true)],
                                          in: context)
        #expect(DayStore.isLockedIn(day, in: context))
        #expect(records.map(\.status) == [.scheduled, .skipped])
        #expect(records[0].scheduledFor == time)
        #expect(records[1].scheduledFor == nil)
        #expect(records[1].skippedAt != nil)
        #expect(records[0].task?.title == "Gym")
        #expect(DayStore.records(on: day, in: context).map(\.title) == ["Gym", "Walk"])
        #expect(DayStore.unresolvedRecords(on: day, in: context).map(\.title) == ["Gym"])
    }

    @Test func statusChanges() throws {
        let context = try makeContext()
        let day = date("2026-10-05")
        let records = try DayStore.lockIn(date: day, dayNote: nil, planName: nil,
                                          items: [item(0, "Gym", time: day.date(hour: 9, minute: 0)),
                                                  item(1, "Study", time: day.date(hour: 10, minute: 0))],
                                          in: context)
        DayStore.markRinging([(key: records[0].alarmKey, firstAlarmAt: day.date(hour: 9, minute: 0))], in: context)
        #expect(records[0].status == .ringing)
        DayStore.markAcknowledged(alarmKey: records[0].alarmKey, snoozeCount: 2, in: context)
        #expect(records[0].status == .inProgress)
        #expect(records[0].snoozeCount == 2)
        try DayStore.log(records[0], as: .done, in: context)
        #expect(records[0].status == .done)
        #expect(records[0].doneAt != nil)
        // A resolved task isn't reopened by a late acknowledgement.
        DayStore.markAcknowledged(alarmKey: records[0].alarmKey, snoozeCount: 5, in: context)
        #expect(records[0].status == .done)
        #expect(records[1].status == .scheduled)
    }

    @Test func oldUnresolvedTasksBecomeUnlogged() throws {
        let context = try makeContext()
        let old = try DayStore.lockIn(date: date("2026-10-03"), dayNote: nil, planName: nil,
                                      items: [item(0, "Old", time: .now)], in: context)
        let yesterday = try DayStore.lockIn(date: date("2026-10-04"), dayNote: nil, planName: nil,
                                            items: [item(0, "Yesterday", time: .now)], in: context)
        let keys = DayStore.markUnlogged(before: date("2026-10-04"), in: context)
        #expect(keys == [old[0].alarmKey])
        #expect(old[0].status == .unlogged)
        #expect(yesterday[0].status == .scheduled)
        #expect(DayStore.unresolvedRecords(on: date("2026-10-04"), in: context).count == 1)
    }
}

struct AlarmRegistryCompatibilityTests {
    @Test func olderSavedDataStillLoads() throws {
        let defaults = try #require(UserDefaults(suiteName: "RegistryCompat-\(UUID().uuidString)"))
        let id = UUID()
        defaults.set(Data(#"{"wakeAlarmIDs":["\#(id.uuidString)"],"tasks":[]}"#.utf8), forKey: AlarmRegistry.defaultsKey)
        let registry = AlarmRegistry.load(from: defaults)
        #expect(registry.wakeAlarmIDs == [id])
        #expect(registry.checkInChains.isEmpty)
        #expect(registry.testAlarmIDs.isEmpty)
    }
}
