import SwiftUI
import UIKit

/// Explains when alarms can't ring, with the button to fix it. Hidden once alarms are allowed.
struct AlarmPermissionBanner: View {
    @State private var alarms = AlarmService.shared

    var body: some View {
        switch alarms.permission {
        case .allowed:
            EmptyView()
        case .denied:
            banner(
                title: "Alarms are turned off",
                message: "PlanAlarm can't ring for your tasks or wake-up. Turn on Alarms for PlanAlarm in Settings.",
                buttonTitle: "Open Settings"
            ) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        case .notAsked:
            banner(
                title: "Allow alarms",
                message: "PlanAlarm needs permission to ring like an alarm, even in silent mode and Focus.",
                buttonTitle: "Allow Alarms"
            ) {
                Task { await alarms.requestAuthorization() }
            }
        }
    }

    private func banner(title: String, message: String, buttonTitle: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "alarm.waves.left.and.right")
                .font(.headline)
            Text(message)
                .font(.subheadline)
            Button(buttonTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
    }
}
