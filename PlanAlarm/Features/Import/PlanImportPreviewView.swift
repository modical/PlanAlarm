import SwiftData
import SwiftUI

/// Shows what a plan contains (or what's wrong with it) before it replaces the active plan.
struct PlanImportPreviewView: View {
    let pending: PendingImport

    @Environment(ImportController.self) private var importer
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<StoredPlan> { $0.isActive == true }) private var activePlans: [StoredPlan]
    @State private var saveError: String?

    private var result: PlanParseResult { pending.result }

    var body: some View {
        NavigationStack {
            List {
                if !result.errors.isEmpty {
                    Section {
                        ForEach(Array(result.errors.enumerated()), id: \.offset) { _, issue in
                            IssueRow(issue: issue, systemImage: "xmark.octagon.fill", tint: .red)
                        }
                    } header: {
                        Text(result.errors.count == 1 ? "1 problem to fix" : "\(result.errors.count) problems to fix")
                    } footer: {
                        Text("Fix these in the plan file (or ask Claude to fix them), then import it again.")
                    }
                }

                if let plan = result.plan {
                    Section("Plan") {
                        LabeledContent("Name", value: plan.name)
                        LabeledContent("Dates", value: plan.dateRangeText)
                        LabeledContent("Tasks", value: plan.taskCountText)
                        LabeledContent("From", value: pending.sourceName)
                    }
                    if let note = plan.timingNote(today: .today()) {
                        Section {
                            Label(note, systemImage: "info.circle")
                        }
                    }
                    if let current = activePlans.first {
                        Section {
                            Label("Replaces “\(current.name)”. It will be archived, and your history is kept.",
                                  systemImage: "archivebox")
                        }
                    }
                    Section("First week") {
                        ForEach(plan.firstWeek) { day in
                            DaySummaryRow(day: day)
                        }
                    }
                }

                if !result.warnings.isEmpty {
                    Section("Warnings") {
                        ForEach(Array(result.warnings.enumerated()), id: \.offset) { _, issue in
                            IssueRow(issue: issue, systemImage: "exclamationmark.triangle.fill", tint: .orange)
                        }
                    }
                }
            }
            .navigationTitle(result.isValid ? "Import Plan" : "Can't Import Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { importer.sheet = nil }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if result.isValid {
                    Button {
                        confirm()
                    } label: {
                        Text("Use This Plan").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding()
                    .background(.bar)
                }
            }
            .alert("Couldn't save the plan", isPresented: .init(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private func confirm() {
        do {
            try importer.confirm(pending, in: modelContext)
        } catch {
            saveError = error.localizedDescription
        }
    }
}

private struct IssueRow: View {
    let issue: PlanIssue
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            Text(issue.description)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(tint)
        }
    }
}
