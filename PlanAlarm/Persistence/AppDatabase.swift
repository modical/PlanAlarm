import Foundation
import SwiftData

/// The app's single SwiftData container. Shared with App Intents (alarm buttons), which run in the
/// app's process and may start while no window is open.
@MainActor
enum AppDatabase {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: StoredPlan.self, AppSettings.self)
        } catch {
            fatalError("Couldn't open the PlanAlarm database: \(error)")
        }
    }()

    static var context: ModelContext { container.mainContext }
}
