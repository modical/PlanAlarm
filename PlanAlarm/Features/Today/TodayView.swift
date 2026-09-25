import SwiftUI

struct TodayView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                AlarmPermissionBanner()
                    .padding(.horizontal)
                ContentUnavailableView(
                    "Your day starts here",
                    systemImage: "alarm",
                    description: Text("The morning check-in and today's task alarms arrive in the next phase.")
                )
            }
            .navigationTitle("Today")
        }
    }
}

#Preview {
    TodayView()
}
