@preconcurrency import CoreMotion
import Foundation
import Observation

/// Counts steps live with the iPhone's motion chip, from the moment it starts (for the wake-up walk).
/// The first start shows iOS's Motion & Fitness prompt.
@MainActor
@Observable
final class StepCounter {
    enum State: Equatable {
        case counting
        /// No step counting on this device (e.g. the Simulator).
        case unavailable
        /// Motion & Fitness access is off for PlanAlarm.
        case denied
    }

    private(set) var steps = 0
    private(set) var state: State
    private let pedometer = CMPedometer()
    private var isRunning = false

    init() {
        state = Self.currentState()
    }

    static func currentState() -> State {
        guard CMPedometer.isStepCountingAvailable() else { return .unavailable }
        switch CMPedometer.authorizationStatus() {
        case .denied, .restricted: return .denied
        default: return .counting
        }
    }

    func start() {
        state = Self.currentState()
        guard state == .counting, !isRunning else { return }
        isRunning = true
        // Core Motion calls this on its own queue, so the handler must not be main-actor isolated.
        pedometer.startUpdates(from: .now) { @Sendable data, error in
            let steps = data?.numberOfSteps.intValue
            let failed = error != nil
            Task { @MainActor in
                self.receive(steps: steps, failed: failed)
            }
        }
    }

    func stop() {
        pedometer.stopUpdates()
        isRunning = false
    }

    private func receive(steps: Int?, failed: Bool) {
        if let steps {
            self.steps = max(self.steps, steps)
        }
        if failed {
            stop()
            let current = Self.currentState()
            state = current == .counting ? .unavailable : current
        }
    }
}
