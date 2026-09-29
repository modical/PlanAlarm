import SwiftData
import SwiftUI
import UIKit
import UserNotifications

@main
struct PlanAlarmApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(AppDatabase.container)
    }
}

/// Sets up the follow-up notifications' Done / Skipped buttons as early as possible, so a button pressed
/// while the app wasn't running is still handled.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        FollowUpService.registerCategory()
        return true
    }
}
