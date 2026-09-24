import SwiftData
import SwiftUI

struct SettingsView: View {
    @Query(filter: #Predicate<StoredPlan> { $0.isActive == true }) private var activePlans: [StoredPlan]

    var body: some View {
        NavigationStack {
            List {
                Section("Plan") {
                    if let stored = activePlans.first {
                        LabeledContent("Current plan", value: stored.name)
                        if let plan = PlanStore.plan(for: stored) {
                            LabeledContent("Dates", value: plan.dateRangeText)
                        }
                        LabeledContent("Imported", value: stored.importedAt.formatted(date: .abbreviated, time: .shortened))
                    } else {
                        Text("No plan loaded").foregroundStyle(.secondary)
                    }
                    ImportPlanButtons()
                }

                Section("About") {
                    LabeledContent("Version", value: AppInfo.version)
                    LabeledContent("Build", value: AppInfo.build)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }
}

#Preview {
    SettingsView()
        .environment(ImportController())
        .modelContainer(for: StoredPlan.self, inMemory: true)
}
