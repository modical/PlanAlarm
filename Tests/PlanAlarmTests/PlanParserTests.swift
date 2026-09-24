import Foundation
import Testing
@testable import PlanAlarm

struct PlanParserTests {
    private func parse(_ json: String) -> PlanParseResult {
        PlanParser.parse(text: json)
    }

    private func messages(_ issues: [PlanIssue]) -> [String] {
        issues.map(\.description)
    }

    // MARK: Valid plans

    @Test func briefExampleParses() throws {
        let result = parse(Fixtures.briefExample)
        #expect(result.errors.isEmpty, "\(result.errors)")
        #expect(result.warnings.isEmpty, "\(result.warnings)")
        let plan = try #require(result.plan)
        #expect(plan.name == "October Cut")
        #expect(plan.startDate == Fixtures.date("2026-10-01"))
        #expect(plan.endDate == Fixtures.date("2026-10-31"))
        #expect(plan.defaultReadSeconds == 30)
        #expect(plan.library.count == 2)
        #expect(plan.library["push-day"]?.sections.count == 3)
    }

    @Test func unknownFieldsAreIgnored() {
        let json = Fixtures.mondayPlan(
            """
            { "title": "A", "category": "gym", "emoji": "💪",
              "description": { "summary": "S", "mood": 1,
                               "sections": [ { "title": "T", "items": ["x"], "color": "red" } ] } }
            """,
            extra: #""author": "Claude", "futureFeature": { "a": 1 }"#
        )
        let result = parse(json)
        #expect(result.isValid, "\(result.errors)")
    }

    @Test func nullEndDateMeansOpenEnded() throws {
        let plan = try #require(parse(Fixtures.mondayPlan(#"{ "title": "A", "category": "x" }"#, extra: #""endDate": null"#)).plan)
        #expect(plan.endDate == nil)
    }

    @Test func byteOrderMarkIsIgnored() {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data(Fixtures.briefExample.utf8)
        #expect(PlanParser.parse(data).isValid)
    }

    @Test func curlyQuotesAreRepaired() throws {
        let curly = Fixtures.mondayPlan(#"{ "title": "A", "category": "x" }"#)
            .replacingOccurrences(of: "\"", with: "\u{201C}")
        let result = parse(curly)
        #expect(result.isValid, "\(result.errors)")
        #expect(result.warnings.first?.message.hasPrefix("Curly quotes") == true)
        let json = try #require(result.json)
        #expect(!String(decoding: json, as: UTF8.self).contains("\u{201C}"))
    }

    // MARK: File-level errors

    @Test func emptyInput() {
        #expect(messages(parse("  \n").errors) == ["The plan is empty."])
    }

    @Test func invalidJSON() {
        let result = parse(#"{ "schemaVersion": 1 "planName": "x" }"#)
        #expect(result.plan == nil)
        #expect(result.errors.count == 1)
        #expect(result.errors.first?.message.hasPrefix("This isn't valid JSON.") == true)
    }

    @Test func topLevelMustBeAnObject() {
        #expect(parse("[1, 2]").errors.first?.message.hasPrefix("The plan must be a JSON object") == true)
    }

    @Test func unknownSchemaVersionIsAClearError() {
        let result = parse(Fixtures.briefExample.replacingOccurrences(of: #""schemaVersion": 1"#, with: #""schemaVersion": 2"#))
        #expect(result.plan == nil)
        #expect(result.errors.count == 1)
        #expect(result.errors.first?.message.hasPrefix("schemaVersion 2 isn't supported.") == true)
    }

    @Test func schemaVersionMustBeANumber() {
        let result = parse(#"{ "schemaVersion": "1", "planName": "x", "startDate": "2026-10-01" }"#)
        #expect(messages(result.errors) == [#"schemaVersion should be the number 1, but found "1"."#])
    }

    @Test func missingSchemaVersion() {
        #expect(parse(#"{ "planName": "x" }"#).errors.first?.message.hasPrefix("Missing schemaVersion.") == true)
    }

    @Test func missingRequiredTopLevelFields() {
        let result = parse(#"{ "schemaVersion": 1 }"#)
        let all = messages(result.errors)
        #expect(all.contains("Missing planName."))
        #expect(all.contains { $0.hasPrefix("Missing startDate.") })
    }

    @Test func endDateBeforeStartDate() {
        let result = parse(Fixtures.minimalPlan(#""endDate": "2026-09-30""#))
        #expect(messages(result.errors) == ["endDate 2026-09-30 is before startDate 2026-10-01."])
    }

    @Test func invalidDates() {
        let result = parse(#"{ "schemaVersion": 1, "planName": "x", "startDate": "2026-10-1", "dateOverrides": { "2026-02-30": { "mode": "add" } } }"#)
        let all = messages(result.errors)
        #expect(all.contains { $0.hasPrefix("startDate '2026-10-1' isn't a valid date.") })
        #expect(all.contains { $0.hasPrefix("dateOverrides: '2026-02-30' isn't a valid date.") })
    }

    // MARK: Task errors

    @Test func invalidSuggestedTimeNamesTheDayAndTask() {
        let result = parse(Fixtures.briefExample.replacingOccurrences(of: #""18:00""#, with: #""25:00""#))
        #expect(result.plan == nil)
        #expect(messages(result.errors) == [
            #"Monday, task 2: suggestedTime '25:00' is not a valid time. Use 24-hour HH:mm, like "07:30" or "18:00"."#,
        ])
    }

    @Test func unknownTaskRefSuggestsTheClosestKey() {
        let result = parse(Fixtures.briefExample.replacingOccurrences(of: #""taskRef": "push-day""#, with: #""taskRef": "push-dya""#))
        #expect(messages(result.errors) == ["Monday, task 2: taskRef 'push-dya' isn't in taskLibrary. Did you mean 'push-day'?"])
    }

    @Test func wrongTypesAreExplained() {
        let result = parse(Fixtures.mondayPlan(#"{ "title": "A", "category": "gym", "durationMinutes": "75" }"#))
        #expect(messages(result.errors) == [#"Monday, task 1: durationMinutes should be a whole number, but found "75"."#])
    }

    @Test func numbersMustBeWholeAndInRange() {
        let result = parse(Fixtures.mondayPlan(#"{ "title": "A", "category": "gym", "durationMinutes": 7.5, "readSeconds": 0 }"#))
        #expect(messages(result.errors) == [
            "Monday, task 1: durationMinutes should be a whole number, but found 7.5.",
            "Monday, task 1: readSeconds must be between 1 and 3600, but is 0.",
        ])
    }

    @Test func inlineTaskNeedsTitleAndCategory() {
        let result = parse(Fixtures.mondayPlan(#"{ "category": "gym" }, { "title": "B" }, { "title": "  ", "category": "x" }"#))
        #expect(messages(result.errors) == [
            "Monday, task 1: needs a title, or a taskRef that points to an entry in taskLibrary.",
            #"Monday, task 2: needs a category, such as "gym", "mobility", "study", "nutrition" or "other"."#,
            "Monday, task 3: title can't be empty.",
        ])
    }

    @Test func brokenLibraryEntryIsReportedOnce() {
        let result = parse(Fixtures.mondayPlan(#"{ "taskRef": "a" }"#, extra: #""taskLibrary": { "a": { "title": "A" } }"#))
        #expect(messages(result.errors) == [
            #"taskLibrary 'a': needs a category, such as "gym", "mobility", "study", "nutrition" or "other"."#,
        ])
    }

    @Test func sectionItemsMustBeText() {
        let result = parse(Fixtures.mondayPlan(
            #"{ "title": "A", "category": "x", "description": { "sections": [ { "title": "S", "items": ["ok", 5] } ] } }"#
        ))
        #expect(messages(result.errors) == ["Monday, task 1, section 1, item 2: should be text, but found 5."])
    }

    @Test func descriptionMustBeAnObject() {
        let result = parse(Fixtures.mondayPlan(#"{ "title": "A", "category": "x", "description": "Just text" }"#))
        #expect(result.errors.first?.description.hasPrefix("Monday, task 1: description should be an object") == true)
    }

    @Test func allProblemsAreReportedTogether() {
        let result = parse(Fixtures.mondayPlan(#"{ "title": "A", "category": "x", "suggestedTime": "7:30" }, { "title": "B" }"#))
        #expect(result.errors.count == 2)
    }

    // MARK: Template and override errors

    @Test func unknownWeekdayIsAnError() {
        let result = parse(Fixtures.minimalPlan(#""weeklyTemplate": { "munday": { "tasks": [] } }"#))
        #expect(result.errors.first?.description.hasPrefix("weeklyTemplate: 'munday' isn't a weekday.") == true)
    }

    @Test func overrideModeIsRequiredAndChecked() {
        let result = parse(Fixtures.minimalPlan(#""dateOverrides": { "2026-10-05": { "tasks": [] }, "2026-10-06": { "mode": "append" } }"#))
        #expect(messages(result.errors) == [
            #"Override 2026-10-05: needs a mode: "add" (add tasks to the normal day) or "replace" (use only these tasks)."#,
            #"Override 2026-10-06: mode 'append' isn't valid. Use "add" or "replace"."#,
        ])
    }

    // MARK: Warnings

    @Test func overrideOutsidePlanIsAWarning() {
        let result = parse(Fixtures.mondayPlan(
            #"{ "title": "A", "category": "x" }"#,
            extra: #""endDate": "2026-10-31", "dateOverrides": { "2026-11-05": { "mode": "add", "tasks": [] } }"#
        ))
        #expect(result.isValid)
        #expect(messages(result.warnings) == ["Override 2026-11-05: this date is outside the plan's dates, so the override will be ignored."])
    }

    @Test func unusedLibraryEntryIsAWarning() {
        let result = parse(Fixtures.mondayPlan(
            #"{ "title": "A", "category": "x" }"#,
            extra: #""taskLibrary": { "spare": { "title": "S", "category": "x" } }"#
        ))
        #expect(result.isValid)
        #expect(messages(result.warnings) == ["taskLibrary 'spare': isn't used on any day."])
    }

    @Test func planWithNoTasksIsAWarning() {
        let result = parse(Fixtures.minimalPlan())
        #expect(result.isValid)
        #expect(messages(result.warnings) == ["This plan has no tasks on any day."])
    }
}
