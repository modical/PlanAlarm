import Testing
@testable import PlanAlarm

struct SmokeTests {
    @Test func hasFourTabs() {
        #expect(AppTab.allCases == [.today, .plan, .history, .settings])
    }

    @Test func appInfoReadsBundle() {
        #expect(!AppInfo.version.isEmpty)
        #expect(!AppInfo.build.isEmpty)
    }
}
