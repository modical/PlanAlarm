import SwiftUI

struct TodayView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No plan yet",
                systemImage: "alarm",
                description: Text("Your daily tasks and alarms will appear here.")
            )
            .navigationTitle("Today")
        }
    }
}

#Preview {
    TodayView()
}
