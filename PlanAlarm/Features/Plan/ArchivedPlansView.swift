import SwiftData
import SwiftUI

struct ArchivedPlansView: View {
    @Query(filter: #Predicate<StoredPlan> { $0.isActive == false },
           sort: \StoredPlan.importedAt, order: .reverse)
    private var archived: [StoredPlan]

    var body: some View {
        List {
            if archived.isEmpty {
                Text("No archived plans yet. When you import a new plan, the old one is kept here.")
                    .foregroundStyle(.secondary)
            }
            ForEach(archived) { stored in
                NavigationLink {
                    if let plan = PlanStore.plan(for: stored) {
                        PlanWeekBrowser(plan: plan)
                            .navigationTitle(stored.name)
                    } else {
                        ContentUnavailableView("Can't read this plan", systemImage: "exclamationmark.triangle")
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stored.name)
                        Text("Imported \(stored.importedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Archived Plans")
    }
}
