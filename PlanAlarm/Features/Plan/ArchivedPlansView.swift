import SwiftData
import SwiftUI

struct ArchivedPlansView: View {
    @Query(filter: #Predicate<StoredPlan> { $0.isActive == false },
           sort: \StoredPlan.importedAt, order: .reverse)
    private var archived: [StoredPlan]
    @Environment(\.modelContext) private var modelContext
    @State private var pendingDelete: StoredPlan?
    @State private var deleteError: String?

    var body: some View {
        List {
            if archived.isEmpty {
                Text("No archived plans yet. When you import or create a new plan, the old one is kept here.")
                    .foregroundStyle(.secondary)
            }
            ForEach(archived) { stored in
                NavigationLink {
                    ArchivedPlanDetail(stored: stored)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stored.name)
                        Text("Imported \(stored.importedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        pendingDelete = stored
                    }
                }
            }
        }
        .navigationTitle("Archived Plans")
        .confirmationDialog(
            "Delete this plan?",
            isPresented: .init(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { stored in
            Button("Delete “\(stored.name)”", role: .destructive) {
                do {
                    try PlanStore.delete(stored, in: modelContext)
                } catch {
                    deleteError = error.localizedDescription
                }
            }
        } message: { _ in
            Text("Your done/skipped history is kept.")
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

private struct ArchivedPlanDetail: View {
    let stored: StoredPlan

    var body: some View {
        Group {
            if let plan = PlanStore.plan(for: stored) {
                PlanWeekBrowser(plan: plan)
            } else {
                ContentUnavailableView("Can't read this plan", systemImage: "exclamationmark.triangle")
            }
        }
        .navigationTitle(stored.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: DayPlanFile(stored), preview: SharePreview(stored.name)) {
                    Label("Share Plan as File", systemImage: "square.and.arrow.up")
                }
            }
        }
    }
}
