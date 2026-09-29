import SwiftUI

/// Shown full screen while a task alarm is waiting to be stopped. The Stop Alarm button unlocks after a
/// countdown that only runs while the app is on screen. Until then the alarm keeps coming back.
/// (Phase 5 adds the Starting now / Reschedule / Skip today actions.)
struct TaskAlarmView: View {
    let pending: PendingTaskAlarm
    let unlockSeconds: Int
    let snoozeCount: Int
    let onStop: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var remaining: Double

    init(pending: PendingTaskAlarm, unlockSeconds: Int, snoozeCount: Int, onStop: @escaping () -> Void) {
        self.pending = pending
        self.unlockSeconds = max(1, unlockSeconds)
        self.snoozeCount = snoozeCount
        self.onStop = onStop
        _remaining = State(initialValue: Double(max(1, unlockSeconds)))
    }

    private var isUnlocked: Bool { remaining <= 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label(statusText, systemImage: "alarm.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                    TaskContentView(task: pending.task)
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    if !isUnlocked {
                        ProgressView(value: Double(unlockSeconds) - remaining, total: Double(unlockSeconds))
                        Text("Stop Alarm unlocks in \(Int(remaining.rounded(.up))) s")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Button(action: onStop) {
                        Label("Stop Alarm", systemImage: isUnlocked ? "stop.circle.fill" : "lock.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!isUnlocked)
                }
                .padding()
                .background(.bar)
            }
            .navigationBarTitleDisplayMode(.inline)
            // The countdown only runs while the app is in the foreground.
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                while remaining > 0 && !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(200))
                    if !Task.isCancelled {
                        remaining = max(0, remaining - 0.2)
                    }
                }
            }
        }
    }

    private var statusText: String {
        let time = pending.firstAlarmAt.formatted(date: .omitted, time: .shortened)
        switch snoozeCount {
        case 0: return "Alarm at \(time)"
        case 1: return "Alarm at \(time) · rang again once"
        default: return "Alarm at \(time) · rang again \(snoozeCount) times"
        }
    }
}
