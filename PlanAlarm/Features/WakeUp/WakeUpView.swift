import SwiftUI
import UIKit

/// The wake-up walk, shown full screen once the wake-up alarm has rung (or early, from Today). The wake-up
/// rings keep coming until the steps are walked; then "I'm Up" stops them. If steps can't be counted
/// (no Motion & Fitness access), staying on this screen for a minute does instead.
struct WakeUpView: View {
    let goal: Int
    /// Opened from Today before the wake-up time: it can be closed without walking.
    let isEarly: Bool
    let onDone: () -> Void
    let onCancel: () -> Void

    static let fallbackSeconds = 60

    @Environment(\.scenePhase) private var scenePhase
    @State private var counter = StepCounter()
    @State private var fallbackRemaining = Double(Self.fallbackSeconds)

    private var isDone: Bool {
        switch counter.state {
        case .counting: counter.steps >= goal
        case .unavailable, .denied: fallbackRemaining <= 0
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 60))
                        .foregroundStyle(.orange)
                    Text(isEarly ? "Up already?" : "Good morning!")
                        .font(.largeTitle.bold())
                    switch counter.state {
                    case .counting: stepsProgress
                    case .denied: fallback(reason: "Motion & Fitness access is off, so steps can't be counted.", showsSettings: true)
                    case .unavailable: fallback(reason: "Steps can't be counted right now.", showsSettings: false)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: onDone) {
                    Label("I'm Up", systemImage: "sun.max.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!isDone)
                .padding()
                .background(.bar)
            }
            .toolbar {
                if isEarly {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onCancel)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
        // Counting and the fallback countdown only run while the app is on screen.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            counter.start()
            while counter.state != .counting && fallbackRemaining > 0 && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                if !Task.isCancelled {
                    fallbackRemaining = max(0, fallbackRemaining - 0.2)
                }
            }
        }
        .onDisappear {
            counter.stop()
        }
    }

    private var stepsProgress: some View {
        VStack(spacing: 14) {
            Text("\(min(counter.steps, goal)) / \(goal)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
            ProgressView(value: Double(min(counter.steps, goal)), total: Double(max(1, goal)))
            Text(isDone
                 ? "Nice. Tap I'm Up to stop the wake-up alarm."
                 : "Get out of bed and walk with your phone. The wake-up alarm keeps ringing until you've walked \(goal) steps.")
                .font(.title3)
        }
    }

    private func fallback(reason: String, showsSettings: Bool) -> some View {
        VStack(spacing: 14) {
            Text(isDone ? "Done." : "\(Int(fallbackRemaining.rounded(.up))) s")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text("\(reason) Stay on this screen for \(Self.fallbackSeconds) seconds instead.")
                .font(.title3)
            if showsSettings {
                Button("Allow Motion & Fitness in Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
