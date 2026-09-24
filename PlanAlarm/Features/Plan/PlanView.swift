import SwiftUI

struct PlanView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No plan loaded",
                systemImage: "list.bullet.rectangle",
                description: Text("Import a .dayplan file to see your week here.")
            )
            .navigationTitle("Plan")
        }
    }
}

#Preview {
    PlanView()
}
