import Foundation
import Testing
@testable import PlanAlarm

struct SamplePlanTests {
    /// Samples/sample-october.dayplan in the repository (the simulator can read the checkout directly).
    static let repoSampleURL = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Samples/sample-october.dayplan")

    private let date = Fixtures.date

    @Test func sampleIsValidWithNoWarnings() throws {
        let result = PlanParser.parse(try Data(contentsOf: Self.repoSampleURL))
        #expect(result.errors.isEmpty, "\(result.errors)")
        #expect(result.warnings.isEmpty, "\(result.warnings)")
        let plan = try #require(result.plan)
        #expect(plan.name == "October Cut")
        #expect(plan.lengthInDays == 31)
        #expect(plan.library.count == 10)

        #expect(plan.day(on: date("2026-10-02")).isRestDay) // Friday
        #expect(plan.day(on: date("2026-10-10")).overrideMode == .replace)
        #expect(plan.day(on: date("2026-10-15")).tasks.last?.title == "Progress photos")
        #expect(plan.day(on: date("2026-10-01")).tasks.contains { $0.suggestedTime == nil })

        let deload = try #require(plan.day(on: date("2026-10-31")).tasks.last)
        #expect(deload.title == "Gym — Light legs (deload)")
        #expect(deload.durationMinutes == 45)
        #expect(deload.sections.count == 3)
        #expect(deload.summary?.hasPrefix("Half the sets") == true)
    }

    @Test func sampleMovesByWholeWeeksToCoverToday() throws {
        let plan = try #require(PlanParser.parse(try Data(contentsOf: Self.repoSampleURL)).plan)
        #expect(plan.movedToCover(date("2026-10-15")) == plan) // already covers it

        let later = plan.movedToCover(date("2027-03-10"))
        #expect(later.contains(date("2027-03-10")))
        #expect(plan.startDate.days(until: later.startDate) % 7 == 0)
        #expect(later.startDate.weekday == plan.startDate.weekday)
        #expect(later.lengthInDays == plan.lengthInDays)
        // The travel day (a Saturday "replace") moves with it and stays a Saturday.
        let travel = try #require(later.dateOverrides.first { $0.value.dayNote == "Travel day — nothing scheduled." }?.key)
        #expect(travel.weekday == .saturday)
        // And it still round-trips as a valid plan.
        #expect(PlanParser.parse(try PlanEncoder.encode(later)).isValid)

        let earlier = plan.movedToCover(date("2026-06-01"))
        #expect(earlier.contains(date("2026-06-01")))
    }

    @Test func sampleIsBundledInTheApp() throws {
        // Only meaningful when the tests run inside the app (the normal, hosted setup).
        guard Bundle.main.bundleIdentifier == "com.habashi.planalarm" else { return }
        let url = try #require(Bundle.main.url(forResource: ImportController.sampleResourceName, withExtension: "dayplan"))
        let bundled = try Data(contentsOf: url)
        let repo = try Data(contentsOf: Self.repoSampleURL)
        #expect(bundled == repo)
    }
}
