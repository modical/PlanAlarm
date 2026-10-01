import Foundation
import Observation

/// App-wide navigation requests (e.g. an alarm's "Open task" button).
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    /// The task alarm whose task should be shown full screen until acknowledged.
    var presentedTaskKey: String?
    /// The day whose wake-up walk is shown full screen.
    var wakeUpDay: LocalDate?

    private init() {}

    /// Shows the wake-up walk once the wake-up alarm has rung and the walk isn't done yet.
    func showWakeUpIfNeeded() {
        guard wakeUpDay == nil, presentedTaskKey == nil,
              let day = AlarmService.shared.pendingWakeUp() else { return }
        wakeUpDay = day
    }

    /// Shows the oldest task that is waiting to be acknowledged, if any (after the wake-up walk).
    func showPendingTaskIfNeeded() {
        guard presentedTaskKey == nil, wakeUpDay == nil,
              let pending = AlarmService.shared.tasksPendingAcknowledgement.first else { return }
        presentedTaskKey = pending.key
    }
}
