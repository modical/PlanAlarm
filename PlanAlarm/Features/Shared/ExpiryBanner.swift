import SwiftUI

/// Warns on Today when this install has under 48 hours left (free Apple ID installs expire after 7 days).
struct ExpiryBanner: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var expiry = AppExpiry.current()

    var body: some View {
        Group {
            if let expiry, expiry.isWarningDue() {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Reinstall PlanAlarm soon", systemImage: "clock.badge.exclamationmark")
                        .font(.headline)
                    Text("This install stops opening \(expiry.date.formatted(.relative(presentation: .named))) (\(expiry.date.formatted(date: .abbreviated, time: .shortened))). Your alarms stop with it. Reinstall with Sideloadly before then; your plan and history are kept.")
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active { expiry = AppExpiry.current() }
        }
    }
}

/// The banners shown at the top of Today: alarm permission and install expiry.
struct TodayBanners: View {
    var body: some View {
        VStack(spacing: 12) {
            AlarmPermissionBanner()
            ExpiryBanner()
        }
    }
}
