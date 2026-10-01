import Foundation
import SwiftData
import Testing
@testable import PlanAlarm

/// Loading, replacing and deleting plans: past days never change, today keeps what it was locked in with,
/// and plans whose start date has passed can be continued or restarted.
@MainActor
struct PlanLifecycleTests {
    private let date = Fixtures.date

    private func briefPlan() throws -> Plan {
        try #require(PlanParser.parse(text: Fixtures.briefExample).plan)
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(for: StoredPlan.self, ExtraTask.self, DayRecord.self, TaskRecord.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func activate(_ plan: Plan, in context: ModelContext) throws -> StoredPlan {
        try PlanStore.activate(plan, json: try PlanEncoder.encode(plan), sourceName: "Test", in: context)
        return try #require(try context.fetch(FetchDescriptor<StoredPlan>(predicate: #Predicate { $0.isActive == true })).first)
    }

    // MARK: Start-date choice

    @Test func continuingSkipsThePastDays() throws {
        let plan = try briefPlan() // Oct 1 – Oct 31
        let continued = try #require(plan.continuing(from: date("2026-10-08")))
        #expect(continued.startDate == date("2026-10-08"))
        #expect(continued.endDate == date("2026-10-31"))
        #expect(continued.dateOverrides.keys.contains(date("2026-10-10")))
        #expect(!continued.dateOverrides.keys.contains(date("2026-10-06"))) // before the new start
        #expect(continued.day(on: date("2026-10-12")) == plan.day(on: date("2026-10-12")))   // days ahead unchanged
        #expect(!continued.day(on: date("2026-10-05")).isInPlan)
        #expect(plan.continuing(from: date("2026-11-02")) == nil) // after the plan ends
        #expect(PlanParser.parse(try PlanEncoder.encode(continued)).isValid)
    }

    @Test func restartingMovesTheWholePlan() throws {
        let plan = try briefPlan()
        let restarted = plan.restarting(on: date("2026-11-10"))
        #expect(restarted.startDate == date("2026-11-10"))
        #expect(restarted.endDate == date("2026-12-10"))
        #expect(restarted.dateOverrides.keys.sorted() == [date("2026-11-15"), date("2026-11-19")]) // +40 days
        #expect(restarted.lengthInDays == plan.lengthInDays)
        // The weekly routine stays on its weekdays.
        #expect(restarted.day(on: date("2026-11-16")).tasks.map(\.title) == ["Morning stretches", "Gym — Push day"]) // a Monday
        #expect(PlanParser.parse(try PlanEncoder.encode(restarted)).isValid)
    }

    @Test func startChoiceDefaultsAndOptions() throws {
        let plan = try briefPlan()
        let today = date("2026-10-08")
        #expect(PlanStartChoice.isNeeded(for: plan, today: today))
        #expect(!PlanStartChoice.isNeeded(for: plan, today: date("2026-10-01")))

        var choice = PlanStartChoice(for: plan, today: today)
        #expect(choice.mode == .continuePlan)
        #expect(choice.apply(to: plan, today: today)?.startDate == today)
        choice.day = .tomorrow
        #expect(choice.apply(to: plan, today: today)?.startDate == date("2026-10-09"))
        choice.day = .other
        choice.otherDate = date("2026-10-20")
        #expect(choice.apply(to: plan, today: today)?.startDate == date("2026-10-20"))
        choice.mode = .restartFromDayOne
        #expect(choice.apply(to: plan, today: today)?.endDate == date("2026-11-19"))

        // A plan that has already ended defaults to starting again from day 1.
        let ended = PlanStartChoice(for: plan, today: date("2026-12-01"))
        #expect(ended.mode == .restartFromDayOne)
        #expect(ended.apply(to: plan, today: date("2026-12-01"))?.startDate == date("2026-12-01"))
    }

    // MARK: Today keeps what it was locked in with

    @Test func lockedInDayIgnoresANewPlan() throws {
        let context = try makeContext()
        let old = try activate(try briefPlan(), in: context)
        let monday = date("2026-10-05")
        let morning = monday.date(hour: 6, minute: 0)
        let items = CheckInPlanner.items(for: DayAgenda.current(on: monday, in: context), planDefaultReadSeconds: 30, now: morning)
        try DayStore.lockIn(date: monday, dayNote: nil, planName: "October Cut", planKey: DayRecord.planKey(for: old),
                            items: items, now: morning, in: context)
        let day = try #require(try context.fetch(FetchDescriptor<DayRecord>()).first)
        #expect(day.follows(old))

        // A different plan (with nothing on Mondays) is loaded.
        let other = Plan.empty(name: "November", startDate: date("2026-10-01"), endDate: nil)
        let new = try activate(other, in: context)
        #expect(!day.follows(new))
        let result = try DayStore.sync(monday, with: DayAgenda.current(on: monday, in: context), planDefaultReadSeconds: 30,
                                       extrasOnly: !day.follows(new), now: morning, in: context)
        #expect(result.removedKeys.isEmpty)
        #expect(DayStore.records(on: monday, in: context).count == 2) // kept

        // The plan is deleted altogether: still kept.
        try PlanStore.delete(new, in: context)
        #expect(!day.follows(nil))
    }

    @Test func daysRecordedBeforePlanTrackingFollowTheActivePlan() throws {
        let day = DayRecord(date: date("2026-10-05"), dayNote: nil, planName: nil, planKey: "")
        #expect(day.follows(nil))
    }

    // MARK: Days that passed without a check-in

    @Test func daysWithoutCheckInAreRecordedFromThePlan() throws {
        let context = try makeContext()
        _ = try activate(try briefPlan(), in: context)
        // Checked in on Sunday Oct 4, then nothing until Friday Oct 9.
        try DayStore.lockIn(date: date("2026-10-04"), dayNote: nil, planName: nil, items: [], in: context)
        let recorded = DayStore.recordDaysWithoutCheckIn(before: date("2026-10-09"), in: context)
        #expect(recorded == [date("2026-10-05"), date("2026-10-06"), date("2026-10-07"), date("2026-10-08")])

        // Monday's two plan tasks were never done: recorded as not logged.
        #expect(DayStore.records(on: date("2026-10-05"), in: context).map(\.status) == [.unlogged, .unlogged])
        // Tuesday had the added study task.
        #expect(DayStore.records(on: date("2026-10-06"), in: context).map(\.title) == ["Study — PMP-style review"])
        // Yesterday (Thursday) had nothing planned: a rest day with no tasks.
        #expect(DayStore.records(on: date("2026-10-08"), in: context).isEmpty)

        // Running it again changes nothing.
        #expect(DayStore.recordDaysWithoutCheckIn(before: date("2026-10-09"), in: context).isEmpty)

        let history = HistoryDay.days(dayRecords: try context.fetch(FetchDescriptor<DayRecord>()),
                                      taskRecords: try context.fetch(FetchDescriptor<TaskRecord>()))
        #expect(HistoryCalculator.kind(on: date("2026-10-05"), days: history, today: date("2026-10-09")) == .missed)
        #expect(HistoryCalculator.kind(on: date("2026-10-08"), days: history, today: date("2026-10-09")) == .restDay)
    }

    @Test func yesterdayWithoutCheckInIsAskedAbout() throws {
        let context = try makeContext()
        _ = try activate(try briefPlan(), in: context)
        try DayStore.lockIn(date: date("2026-10-04"), dayNote: nil, planName: nil, items: [], in: context)
        DayStore.recordDaysWithoutCheckIn(before: date("2026-10-06"), in: context) // records Monday Oct 5
        let open = DayStore.unresolvedRecords(on: date("2026-10-05"), in: context)
        #expect(open.map(\.title) == ["Morning stretches", "Gym — Push day"])
        #expect(open.allSatisfy { $0.status == .scheduled })
        try DayStore.log(open[1], as: .done, in: context)  // "I did go to the gym"
        let history = HistoryDay.days(dayRecords: try context.fetch(FetchDescriptor<DayRecord>()),
                                      taskRecords: try context.fetch(FetchDescriptor<TaskRecord>()))
        #expect(HistoryCalculator.kind(on: date("2026-10-05"), days: history, today: date("2026-10-06")) == .inProgress
                || HistoryCalculator.kind(on: date("2026-10-05"), days: history, today: date("2026-10-06")) == .partial)
    }

    @Test func noHistoryMeansNothingIsRecorded() throws {
        let context = try makeContext()
        _ = try activate(try briefPlan(), in: context)
        #expect(DayStore.recordDaysWithoutCheckIn(before: date("2026-10-09"), in: context).isEmpty)
    }

    // MARK: Past days never change with the plan

    @Test func pastDaysSurviveReplacingAndDeletingThePlan() throws {
        let context = try makeContext()
        let stored = try activate(try briefPlan(), in: context)
        let monday = date("2026-10-05")
        let items = CheckInPlanner.items(for: DayAgenda.current(on: monday, in: context), planDefaultReadSeconds: 30,
                                         now: monday.date(hour: 6, minute: 0))
        let records = try DayStore.lockIn(date: monday, dayNote: "Push day.", planName: "October Cut",
                                          planKey: DayRecord.planKey(for: stored), items: items, in: context)
        try DayStore.log(records[0], as: .done, in: context)

        _ = try activate(Plan.empty(name: "Other", startDate: date("2026-10-01"), endDate: nil), in: context)
        try PlanStore.delete(try #require(try context.fetch(FetchDescriptor<StoredPlan>(predicate: #Predicate { $0.isActive == true })).first),
                             in: context)

        let kept = DayStore.records(on: monday, in: context)
        #expect(kept.map(\.title) == ["Morning stretches", "Gym — Push day"])
        #expect(kept.map(\.status) == [.done, .scheduled])

        // The only way a past day changes: deleting a task by hand.
        try DayStore.deleteRecord(kept[1], in: context)
        #expect(DayStore.records(on: monday, in: context).map(\.title) == ["Morning stretches"])
    }
}
