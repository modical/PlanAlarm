import SwiftData
import SwiftUI

@main
struct PlanAlarmApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: StoredPlan.self)
    }
}
