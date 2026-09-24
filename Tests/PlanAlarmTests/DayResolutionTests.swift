import Foundation
import Testing
@testable import PlanAlarm

struct DayResolutionTests {
    private let date = Fixtures.date

    private func makePlan(_ json: String) throws -> Plan {
        let result = PlanParser.parse(text: json)
        #expect(result.errors.isEmpty, "\(result.errors)")
        return try #require(result.plan)
    }

    @Test func weekdayTemplate() throws {
        let day = try makePlan(Fixtures.briefExample).day(on: date("2026-10-05")) // Monday
        #expect(day.isInPlan)
        #expect(day.overrideMode == nil)
        #expect(day.dayNote == "Push day. Target ~2,200 kcal.")
        #expect(day.tasks.map(\.title) == ["Morning stretches", "Gym — Push day"])
        #expect(day.tasks.map(\.suggestedTime?.description) == ["07:30", "18:00"])
    }

    @Test func briefOverrides() throws {
        let plan = try makePlan(Fixtures.briefExample)

        let added = plan.day(on: date("2026-10-06")) // Tuesday, "add"
        #expect(added.overrideMode == .add)
        #expect(added.dayNote == nil)
        #expect(added.tasks.map(\.title) == ["Study — PMP-style review"])
        #expect(added.tasks.first?.readSeconds == 30)

        let replaced = plan.day(on: date("2026-10-10")) // Saturday, "replace"
        #expect(replaced.overrideMode == .replace)
        #expect(replaced.dayNote == "Travel day — nothing scheduled.")
        #expect(replaced.tasks.isEmpty)
        #expect(replaced.isRestDay)

        let friday = plan.day(on: date("2026-10-09"))
        #expect(friday.dayNote == "Rest day.")
        #expect(friday.isRestDay)
        #expect(friday.overrideMode == nil)
    }

    @Test func daysOutsideThePlanHaveNoTasks() throws {
        let plan = try makePlan(Fixtures.briefExample)
        for iso in ["2026-09-28", "2026-09-30", "2026-11-01", "2026-11-02"] {
            let day = plan.day(on: date(iso))
            #expect(!day.isInPlan, "\(iso)")
            #expect(day.tasks.isEmpty && day.dayNote == nil, "\(iso)")
        }
        #expect(plan.day(on: date("2026-10-01")).isInPlan)
        #expect(plan.day(on: date("2026-10-31")).isInPlan)
    }

    private static let overridePlan = """
    { "schemaVersion": 1, "planName": "T", "startDate": "2026-10-01",
      "weeklyTemplate": { "monday": { "dayNote": "Template", "tasks": [ { "title": "A", "category": "x" } ] } },
      "dateOverrides": {
        "2026-10-05": { "mode": "add", "dayNote": "Override", "tasks": [ { "title": "B", "category": "x" } ] },
        "2026-10-12": { "mode": "add", "tasks": [ { "title": "C", "category": "x" } ] },
        "2026-10-19": { "mode": "replace", "tasks": [ { "title": "D", "category": "x" } ] },
        "2026-10-26": { "mode": "replace" }
      } }
    """

    @Test func addAppendsAndReplacesNoteOnlyIfGiven() throws {
        let plan = try makePlan(Self.overridePlan)
        let withNote = plan.day(on: date("2026-10-05"))
        #expect(withNote.dayNote == "Override")
        #expect(withNote.tasks.map(\.title) == ["A", "B"])

        let withoutNote = plan.day(on: date("2026-10-12"))
        #expect(withoutNote.dayNote == "Template")
        #expect(withoutNote.tasks.map(\.title) == ["A", "C"])
    }

    @Test func replaceSwapsTheWholeDay() throws {
        let plan = try makePlan(Self.overridePlan)
        let replaced = plan.day(on: date("2026-10-19"))
        #expect(replaced.dayNote == nil)
        #expect(replaced.tasks.map(\.title) == ["D"])

        let emptied = plan.day(on: date("2026-10-26"))
        #expect(emptied.overrideMode == .replace)
        #expect(emptied.dayNote == nil)
        #expect(emptied.tasks.isEmpty)
    }

    @Test func openEndedPlanAndMissingWeekdays() throws {
        let plan = try makePlan(Self.overridePlan)
        #expect(plan.endDate == nil)
        let farMonday = date("2026-10-05").adding(days: 7 * 520)
        #expect(farMonday.weekday == .monday)
        #expect(plan.day(on: farMonday).tasks.map(\.title) == ["A"])
        #expect(plan.day(on: farMonday.adding(days: 1)).tasks.isEmpty) // Tuesday isn't in the template
        #expect(plan.totalScheduledTasks == nil)
        #expect(plan.tasksPerTemplateWeek == 1)
    }

    @Test func taskRefFieldsOverrideTheLibrary() throws {
        let json = Fixtures.briefExample.replacingOccurrences(
            of: #"{ "taskRef": "push-day", "suggestedTime": "18:00" }"#,
            with: #"{ "taskRef": "push-day", "title": "Push (short)", "durationMinutes": 45, "readSeconds": 20, "suggestedTime": "19:00", "description": { "summary": "Short version" } }"#
        )
        let task = try #require(try makePlan(json).day(on: date("2026-10-05")).tasks.last)
        #expect(task.taskRef == "push-day")
        #expect(task.title == "Push (short)")
        #expect(task.category == "gym")
        #expect(task.durationMinutes == 45)
        #expect(task.readSeconds == 20)
        #expect(task.suggestedTime == TimeOfDay(hour: 19, minute: 0))
        #expect(task.summary == "Short version")
        #expect(task.sections.map(\.title) == ["Warm-up", "Main", "Finisher"]) // kept from the library
    }

    @Test func taskRefWithoutOverridesMatchesTheLibrary() throws {
        let plan = try makePlan(Fixtures.briefExample)
        var task = try #require(plan.day(on: date("2026-10-05")).tasks.last)
        task.suggestedTime = nil
        #expect(task == plan.library["push-day"])
    }

    @Test func readSecondsFallbackChain() throws {
        let tasks = #"{ "title": "Plain", "category": "x" }, { "title": "Own", "category": "x", "readSeconds": 10 }, { "taskRef": "lib" }"#
        let library = #""taskLibrary": { "lib": { "title": "Lib", "category": "x", "readSeconds": 60 } }"#

        let noDefaults = try makePlan(Fixtures.mondayPlan(tasks, extra: library)).day(on: date("2026-10-05"))
        #expect(noDefaults.tasks.map(\.readSeconds) == [30, 10, 60])

        let withDefaults = try makePlan(Fixtures.mondayPlan(tasks, extra: library + #", "defaults": { "readSeconds": 45 }"#))
            .day(on: date("2026-10-05"))
        #expect(withDefaults.tasks.map(\.readSeconds) == [45, 10, 60])
    }

    @Test func planTotals() throws {
        let plan = try makePlan(Fixtures.briefExample)
        #expect(plan.lengthInDays == 31)
        // 4 Mondays × 2 tasks + 1 added study task.
        #expect(plan.totalScheduledTasks == 9)
        #expect(plan.firstWeek.map(\.date) == (0..<7).map { date("2026-10-01").adding(days: $0) })
    }
}
