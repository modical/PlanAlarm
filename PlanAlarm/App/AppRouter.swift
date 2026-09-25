import Foundation
import Observation

/// App-wide navigation requests (e.g. an alarm's "Open task" button).
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    /// The task alarm whose task should be shown full screen until acknowledged.
    var presentedTaskKey: String?

    private init() {}

    /// Shows the oldest task that is waiting to be acknowledged, if any.
    func showPendingTaskIfNeeded() {
        guard presentedTaskKey == nil,
              let pending = AlarmService.shared.tasksPendingAcknowledgement.first else { return }
        presentedTaskKey = pending.key
    }
}
