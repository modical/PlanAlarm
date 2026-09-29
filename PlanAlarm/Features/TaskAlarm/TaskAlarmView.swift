import SwiftUI

/// The read-to-dismiss screen, shown full screen while a task alarm is waiting. The whole task is shown
/// in large type; after a countdown (which only runs while the app is on screen) three choices unlock,
/// and each one stops the alarm: Starting Now, Reschedule, or Skip Today. Until then the alarm keeps
/// coming back.
struct TaskAlarmView: View {
    let pending: PendingTaskAlarm
    let unlockSeconds: Int
    let snoozeCount: Int
    let onStart: () -> Void
    let onReschedule: (Date) -> Void
    let onSkip: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var remaining: Double
    @State private var isPickingTime = false

    init(pending: PendingTaskAlarm, unlockSeconds: Int, snoozeCount: Int,
         onStart: @escaping () -> Void, onReschedule: @escaping (Date) -> Void, onSkip: @escaping () -> Void) {
        self.pending = pending
        self.unlockSeconds = max(1, unlockSeconds)
        self.snoozeCount = snoozeCount
        self.onStart = onStart
        self.onReschedule = onReschedule
        self.onSkip = onSkip
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
                actionBar
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
            .sheet(isPresented: $isPickingTime) {
                NewTimeSheet(title: pending.task.title) { time in
                    onReschedule(time)
                }
            }
        }
    }

    private var actionBar: some View {
        VStack(spacing: 10) {
            if isUnlocked {
                Text("Stop the alarm:")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                ProgressView(value: Double(unlockSeconds) - remaining, total: Double(unlockSeconds))
                Label("Read the task — the buttons unlock in \(Int(remaining.rounded(.up))) s", systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Button(action: onStart) {
                Label("Starting Now", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            HStack(spacing: 10) {
                Button {
                    isPickingTime = true
                } label: {
                    Label("Reschedule", systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity)
                }
                Button(action: onSkip) {
                    Label("Skip Today", systemImage: "forward.fill")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .disabled(!isUnlocked)
        .padding()
        .background(.bar)
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
