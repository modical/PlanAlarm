import SwiftUI

/// Shown full screen while a task alarm is waiting to be acknowledged.
/// (Phase 5 turns this into the read-to-dismiss screen with a countdown and three actions.)
struct TaskAlarmView: View {
    let pending: PendingTaskAlarm
    let onAcknowledge: () -> Void

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
                Button(action: onAcknowledge) {
                    Text("I've Read It — Stop the Alarm")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
                .background(.bar)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var statusText: String {
        let time = pending.firstAlarmAt.formatted(date: .omitted, time: .shortened)
        switch pending.snoozeCount {
        case 0: return "Alarm at \(time)"
        case 1: return "Alarm at \(time) · snoozed once"
        default: return "Alarm at \(time) · snoozed \(pending.snoozeCount) times"
        }
    }
}
