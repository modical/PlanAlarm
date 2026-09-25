import Foundation
import Testing
@testable import PlanAlarm

struct PlanEditingTests {
    private let date = Fixtures.date

    private func briefPlan() throws -> Plan {
        try #require(PlanParser.parse(text: Fixtures.briefExample).plan)
    }

    private func samplePlan() throws -> Plan {
        try #require(PlanParser.parse(try Data(contentsOf: SamplePlanTests.repoSampleURL)).plan)
    }

    /// Encodes and re-parses, requiring no errors.
    private func roundTrip(_ plan: Plan) throws -> Plan {
        let result = PlanParser.parse(try PlanEncoder.encode(plan))
        #expect(result.errors.isEmpty, "\(result.errors)")
        return try #require(result.plan)
    }

    private func task(_ title: String, at time: String? = nil) -> PlanTask {
        PlanTask(taskRef: nil, title: title, category: "other", summary: nil, sections: [],
                 durationMinutes: nil, readSeconds: 30, suggestedTime: time.flatMap { TimeOfDay(string: $0) })
    }

    // MARK: Encoding

    @Test func encodingRoundTripsExactly() throws {
        let brief = try briefPlan()
        #expect(try roundTrip(brief) == brief)
        let sample = try samplePlan()
        #expect(try roundTrip(sample) == sample)
    }

    @Test func encodedLibraryReferencesStayCompact() throws {
        let json = String(decoding: try PlanEncoder.encode(try briefPlan()), as: UTF8.self)
        #expect(json.contains("\"taskRef\""))
        #expect(!json.contains("1.0")) // whole numbers are written without ".0"
    }

    @Test func emptyPlanIsValid() throws {
        let empty = Plan.empty(name: "Fresh start", startDate: date("2026-11-01"), endDate: date("2026-11-30"))
        let result = PlanParser.parse(try PlanEncoder.encode(empty))
        #expect(result.isValid)
        #expect(result.plan == empty)
        #expect(result.warnings.map(\.message) == ["This plan has no tasks on any day."])
    }

    // MARK: Adding

    @Test func addingToATemplateDayCreatesAnAddOverride() throws {
        var plan = try briefPlan()
        try plan.addTask(task("Walk", at: "20:00"), on: date("2026-10-05"))
        let monday = plan.day(on: date("2026-10-05"))
        #expect(monday.overrideMode == .add)
        #expect(monday.dayNote == "Push day. Target ~2,200 kcal.")
        #expect(monday.tasks.map(\.title) == ["Morning stretches", "Gym — Push day", "Walk"])
        #expect(plan.day(on: date("2026-10-12")).tasks.count == 2) // next Monday unchanged
        #expect(try roundTrip(plan) == plan)
    }

    @Test func addingExtendsAnExistingOverride() throws {
        var plan = try briefPlan()
        try plan.addTask(task("Extra"), on: date("2026-10-06")) // already "add"
        #expect(plan.day(on: date("2026-10-06")).tasks.map(\.title) == ["Study — PMP-style review", "Extra"])
        try plan.addTask(task("Pack bags"), on: date("2026-10-10")) // already "replace"
        let travel = plan.day(on: date("2026-10-10"))
        #expect(travel.overrideMode == .replace)
        #expect(travel.dayNote == "Travel day — nothing scheduled.")
        #expect(travel.tasks.map(\.title) == ["Pack bags"])
        #expect(try roundTrip(plan) == plan)
    }

    @Test func addingToAnEmptyPlan() throws {
        var plan = Plan.empty(name: "Fresh", startDate: date("2026-11-01"), endDate: nil)
        try plan.addTask(task("First"), on: date("2026-11-03"))
        #expect(plan.day(on: date("2026-11-03")).tasks.map(\.title) == ["First"])
        #expect(plan.day(on: date("2026-11-04")).tasks.isEmpty)
        #expect(try roundTrip(plan) == plan)
    }

    @Test func cannotEditOutsideThePlan() throws {
        var plan = try briefPlan()
        #expect(throws: PlanEditError.outsidePlan(date("2026-11-05"))) {
            try plan.addTask(task("Late"), on: date("2026-11-05"))
        }
        #expect(throws: PlanEditError.outsidePlan(date("2026-09-30"))) {
            try plan.clearDay(date("2026-09-30"))
        }
    }

    // MARK: Deleting and clearing

    @Test func deletingFromATemplateDayOnlyChangesThatDate() throws {
        var plan = try briefPlan()
        try plan.deleteTask(at: 0, on: date("2026-10-05"))
        let monday = plan.day(on: date("2026-10-05"))
        #expect(monday.overrideMode == .replace)
        #expect(monday.dayNote == "Push day. Target ~2,200 kcal.")
        #expect(monday.tasks.map(\.title) == ["Gym — Push day"])
        #expect(monday.tasks.first?.taskRef == "push-day")
        #expect(plan.day(on: date("2026-10-12")).tasks.count == 2)
        #expect(try roundTrip(plan) == plan)
    }

    @Test func deletingAnAddedTask() throws {
        var plan = try briefPlan()
        try plan.deleteTask(at: 0, on: date("2026-10-06"))
        let tuesday = plan.day(on: date("2026-10-06"))
        #expect(tuesday.tasks.isEmpty)
        #expect(tuesday.dayNote == nil)
        #expect(try roundTrip(plan) == plan)
    }

    @Test func deletingAMissingTaskThrows() throws {
        var plan = try briefPlan()
        #expect(throws: PlanEditError.taskNotFound) {
            try plan.deleteTask(at: 5, on: date("2026-10-05"))
        }
    }

    @Test func clearingADayKeepsItsNote() throws {
        var plan = try samplePlan()
        try plan.clearDay(date("2026-10-05"))
        let monday = plan.day(on: date("2026-10-05"))
        #expect(monday.tasks.isEmpty)
        #expect(monday.isRestDay)
        #expect(monday.dayNote == "Push day. Target ~2,200 kcal.")
        #expect(plan.day(on: date("2026-10-12")).tasks.count == 4)
        #expect(try roundTrip(plan) == plan)
    }

    @Test func editsKeepLibraryTaskDetails() throws {
        var plan = try samplePlan()
        try plan.deleteTask(at: 0, on: date("2026-10-31")) // leaves the deload leg day (a taskRef with overrides)
        let deload = try #require(try roundTrip(plan).day(on: date("2026-10-31")).tasks.first)
        #expect(deload.title == "Gym — Light legs (deload)")
        #expect(deload.durationMinutes == 45)
        #expect(deload.sections.count == 3)
    }
}
