import SwiftData
import SwiftUI

/// Creates an empty plan (name + dates). Tasks are then added date by date in the Plan tab.
struct NewPlanView: View {
    @Environment(ImportController.self) private var importer
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<StoredPlan> { $0.isActive == true }) private var activePlans: [StoredPlan]

    @State private var name = ""
    @State private var start = Date.now
    @State private var hasEnd = true
    @State private var end = Calendar.plan.date(byAdding: .day, value: 29, to: .now) ?? .now
    @State private var saveError: String?

    private var startDate: LocalDate { LocalDate(start) }
    private var endDate: LocalDate? { hasEnd ? LocalDate(end) : nil }
    private var canCreate: Bool {
        !name.trimmed.isEmpty && (endDate.map { $0 >= startDate } ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Plan name", text: $name)
                }
                Section {
                    DatePicker("Starts", selection: $start, displayedComponents: .date)
                    Toggle("Has an end date", isOn: $hasEnd)
                    if hasEnd {
                        DatePicker("Ends", selection: $end, in: start..., displayedComponents: .date)
                    }
                } footer: {
                    Text("After you create the plan, add tasks to each date in the Plan tab.")
                }
                if let current = activePlans.first {
                    Section {
                        Label("Replaces “\(current.name)”. It will be archived, and your history is kept.",
                              systemImage: "archivebox")
                    }
                }
            }
            .environment(\.calendar, .plan)
            .navigationTitle("New Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { importer.sheet = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(!canCreate)
                }
            }
            .alert("Couldn't create the plan", isPresented: .init(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private func create() {
        let plan = Plan.empty(name: name.trimmed, startDate: startDate, endDate: endDate)
        do {
            try importer.create(plan, in: modelContext)
        } catch {
            saveError = error.localizedDescription
        }
    }
}
