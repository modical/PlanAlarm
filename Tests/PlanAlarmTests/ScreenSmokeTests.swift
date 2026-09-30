import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import PlanAlarm

/// Opens real screens with realistic data and lets them lay out, so crashes that only happen when a
/// screen is shown (not in the pure logic) are caught in CI.
@MainActor
struct ScreenSmokeTests {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: StoredPlan.self, AppSettings.self, ExtraTask.self, DayRecord.self, TaskRecord.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func task(_ title: String, _ category: String) -> PlanTask {
        PlanTask(taskRef: nil, title: title, category: category, summary: "Summary", sections: [],
                 durationMinutes: 30, readSeconds: 30, suggestedTime: nil)
    }

    /// A few days of history like a real week: done, partial, skipped, a rest day, a missed day, and today.
    private func fillHistory(_ context: ModelContext) throws {
        let today = LocalDate.today()
        func lockIn(_ offset: Int, _ tasks: [(String, String)]) throws -> [TaskRecord] {
            let day = today.adding(days: offset)
            let items = tasks.enumerated().map { index, entry in
                CheckInItem(id: index, task: task(entry.0, entry.1), isExtra: false, time: day.date(hour: 9 + index, minute: 0))
            }
            return try DayStore.lockIn(date: day, dayNote: "Note", planName: "Plan", items: items,
                                       now: day.date(hour: 7, minute: 0), in: context)
        }
        let fiveAgo = try lockIn(-5, [("Gym", "gym"), ("Study", "study")])
        try fiveAgo.forEach { try DayStore.log($0, as: .done, in: context) }
        let fourAgo = try lockIn(-4, [("Gym", "gym"), ("Study", "study")])
        try DayStore.log(fourAgo[0], as: .done, in: context)
        try DayStore.log(fourAgo[1], as: .skipped, in: context)
        _ = try lockIn(-3, [])                       // rest day
        // -2: missed (no check-in)
        let yesterday = try lockIn(-1, [("Gym", "Gym"), ("Walk", "other")])
        try DayStore.log(yesterday[0], as: .done, in: context)
        let todays = try lockIn(0, [("Gym", "gym"), ("Study", "study"), ("Stretch", "mobility")])
        try DayStore.log(todays[0], as: .done, in: context)
        DayStore.markAcknowledged(alarmKey: todays[1].alarmKey, snoozeCount: 2, in: context)
    }

    /// Hosts a view in a real window and lets it lay out a few times.
    private func show<V: View>(_ view: V, container: ModelContainer) async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let host = UIHostingController(rootView: view.modelContainer(container).environment(ImportController()))
        window.rootViewController = host
        window.makeKeyAndVisible()
        for _ in 0..<5 {
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(200))
        }
        window.isHidden = true
    }

    @Test func historyTabWithData() async throws {
        let container = try makeContainer()
        try fillHistory(container.mainContext)
        try await show(HistoryView(), container: container)
    }

    @Test func historyTabEmpty() async throws {
        try await show(HistoryView(), container: try makeContainer())
    }

    @Test func todayTabWithData() async throws {
        let container = try makeContainer()
        try fillHistory(container.mainContext)
        try await show(TodayView(date: .today()), container: container)
    }

    @Test func settingsTab() async throws {
        let container = try makeContainer()
        _ = AppSettings.current(in: container.mainContext)
        try await show(SettingsView(), container: container)
    }
}
