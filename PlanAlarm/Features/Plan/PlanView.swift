import SwiftData
import SwiftUI

struct PlanView: View {
    @Query(sort: \StoredPlan.importedAt, order: .reverse) private var plans: [StoredPlan]

    private var active: StoredPlan? { plans.first(where: \.isActive) }
    private var archivedCount: Int { plans.count(where: { !$0.isActive }) }

    var body: some View {
        NavigationStack {
            Group {
                if let active, let plan = PlanStore.plan(for: active) {
                    PlanWeekBrowser(plan: plan, archivedCount: archivedCount)
                        .id(active.id)
                } else {
                    ContentUnavailableView {
                        Label("No plan loaded", systemImage: "list.bullet.rectangle")
                    } description: {
                        Text("Import a .dayplan file, paste plan JSON, or try the sample plan.")
                    } actions: {
                        ImportPlanButtons()
                    }
                }
            }
            .navigationTitle(active?.name ?? "Plan")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ImportPlanButtons()
                    } label: {
                        Label("Import Plan", systemImage: "square.and.arrow.down")
                    }
                }
            }
        }
    }
}

#Preview {
    PlanView()
        .environment(ImportController())
        .modelContainer(for: StoredPlan.self, inMemory: true)
}
