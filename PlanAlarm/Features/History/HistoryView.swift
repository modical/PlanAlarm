import SwiftUI

struct HistoryView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No history yet",
                systemImage: "calendar",
                description: Text("Completed days and streaks will appear here.")
            )
            .navigationTitle("History")
        }
    }
}

#Preview {
    HistoryView()
}
