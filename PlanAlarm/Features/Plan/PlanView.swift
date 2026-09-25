import SwiftData
import SwiftUI

struct PlanView: View {
    @Query(sort: \StoredPlan.importedAt, order: .reverse) private var plans: [StoredPlan]
    @Environment(\.modelContext) private var modelContext
    @State private var isConfirmingDelete = false
    @State private var deleteError: String?

    private var active: StoredPlan? { plans.first(where: \.isActive) }
    private var archivedCount: Int { plans.count(where: { !$0.isActive }) }

    var body: some View {
        NavigationStack {
            Group {
                if let active, let plan = PlanStore.plan(for: active) {
                    PlanWeekBrowser(plan: plan, stored: active, archivedCount: archivedCount)
                        .id(active.id)
                } else {
                    ContentUnavailableView {
                        Label("No plan loaded", systemImage: "list.bullet.rectangle")
                    } description: {
                        Text("Import a .dayplan file, paste plan JSON, create an empty plan, or try the sample plan.")
                    } actions: {
                        ImportPlanButtons()
                    }
                }
            }
            .navigationTitle(active?.name ?? "Plan")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if let active {
                            ShareLink(item: DayPlanFile(active), preview: SharePreview(active.name)) {
                                Label("Share Plan as File…", systemImage: "square.and.arrow.up")
                            }
                            Divider()
                        }
                        ImportPlanButtons()
                        if active != nil {
                            Divider()
                            Button("Delete Plan…", systemImage: "trash", role: .destructive) {
                                isConfirmingDelete = true
                            }
                        }
                    } label: {
                        Label("Plan Options", systemImage: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog(
                "Delete “\(active?.name ?? "")”?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Plan", role: .destructive) { deleteActive() }
            } message: {
                Text("Your done/skipped history is kept. You'll have no plan until you import or create one.")
            }
            .alert("Couldn't delete the plan", isPresented: .init(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(deleteError ?? "")
            }
        }
    }

    private func deleteActive() {
        guard let active else { return }
        do {
            try PlanStore.delete(active, in: modelContext)
        } catch {
            deleteError = error.localizedDescription
        }
    }
}

#Preview {
    PlanView()
        .environment(ImportController())
        .modelContainer(for: StoredPlan.self, inMemory: true)
}
