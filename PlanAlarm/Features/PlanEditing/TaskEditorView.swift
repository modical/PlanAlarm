import SwiftUI

/// Adds a task to one date. Can start from a task in the plan's library; the result is saved
/// as a complete inline task, so later library changes don't alter it.
struct TaskEditorView: View {
    let date: LocalDate
    let plan: Plan
    let onSave: (PlanTask) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var libraryKey: String?
    @State private var title = ""
    @State private var category = ""
    @State private var hasTime = true
    @State private var time: Date
    @State private var hasDuration = false
    @State private var duration = 30
    @State private var readSeconds: Int
    @State private var summary = ""
    @State private var sections: [EditableSection] = []

    private struct EditableSection: Identifiable {
        let id = UUID()
        var title = ""
        var itemsText = ""
    }

    init(date: LocalDate, plan: Plan, onSave: @escaping (PlanTask) -> Void) {
        self.date = date
        self.plan = plan
        self.onSave = onSave
        _readSeconds = State(initialValue: plan.defaultReadSeconds)
        _time = State(initialValue: date.date(hour: 9, minute: 0))
    }

    private var categorySuggestions: [String] {
        let fromPlan = plan.library.values.map(\.category)
        return Array(Set(["gym", "mobility", "study", "nutrition", "other"] + fromPlan)).sorted()
    }

    private var canSave: Bool {
        !title.trimmed.isEmpty && !category.trimmed.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("For \(date.longText) only. Other days don't change.")
                        .foregroundStyle(.secondary)
                    if !plan.library.isEmpty {
                        Picker("Start from", selection: $libraryKey) {
                            Text("New task").tag(String?.none)
                            ForEach(plan.library.keys.sorted(), id: \.self) { key in
                                Text(plan.library[key]?.title ?? key).tag(String?.some(key))
                            }
                        }
                    }
                }

                Section("Task") {
                    TextField("Title", text: $title)
                    HStack {
                        TextField("Category", text: $category)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Menu("Choose") {
                            ForEach(categorySuggestions, id: \.self) { suggestion in
                                Button(suggestion) { category = suggestion }
                            }
                        }
                    }
                }

                Section("Time") {
                    Toggle("Set a time", isOn: $hasTime)
                    if hasTime {
                        DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    }
                    Toggle("Duration", isOn: $hasDuration)
                    if hasDuration {
                        Stepper("\(duration) min", value: $duration, in: 5...600, step: 5)
                    }
                    Stepper("Read for \(readSeconds) s", value: $readSeconds, in: 5...600, step: 5)
                }

                Section("Description") {
                    TextField("Summary (optional)", text: $summary, axis: .vertical)
                        .lineLimit(2...6)
                }

                ForEach($sections) { $section in
                    Section {
                        TextField("Section title, e.g. Warm-up", text: $section.title)
                        TextField("Items, one per line", text: $section.itemsText, axis: .vertical)
                            .lineLimit(3...12)
                        Button("Remove Section", role: .destructive) {
                            let id = section.id
                            sections.removeAll { $0.id == id }
                        }
                    }
                }

                Section {
                    Button("Add Section", systemImage: "plus") {
                        sections.append(EditableSection())
                    }
                } footer: {
                    Text("Sections are lists shown on the read screen, e.g. a Warm-up list and a Main list.")
                }
            }
            .environment(\.calendar, .plan)
            .navigationTitle("Add Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(!canSave)
                }
            }
            .onChange(of: libraryKey) {
                fillFromLibrary()
            }
        }
    }

    private func fillFromLibrary() {
        guard let libraryKey, let task = plan.library[libraryKey] else { return }
        title = task.title
        category = task.category
        hasTime = task.suggestedTime != nil
        if let suggested = task.suggestedTime {
            time = date.date(hour: suggested.hour, minute: suggested.minute)
        }
        hasDuration = task.durationMinutes != nil
        duration = task.durationMinutes ?? duration
        readSeconds = task.readSeconds
        summary = task.summary ?? ""
        sections = task.sections.map { EditableSection(title: $0.title, itemsText: $0.items.joined(separator: "\n")) }
    }

    private func save() {
        let parts = Calendar.plan.dateComponents([.hour, .minute], from: time)
        let taskSections: [TaskSection] = sections.compactMap { section in
            let items = section.itemsText
                .split(separator: "\n")
                .map { String($0).trimmed }
                .filter { !$0.isEmpty }
            let sectionTitle = section.title.trimmed
            guard !sectionTitle.isEmpty || !items.isEmpty else { return nil }
            return TaskSection(title: sectionTitle.isEmpty ? "Details" : sectionTitle, items: items)
        }
        let task = PlanTask(
            taskRef: nil,
            title: title.trimmed,
            category: category.trimmed,
            summary: summary.trimmed.isEmpty ? nil : summary.trimmed,
            sections: taskSections,
            durationMinutes: hasDuration ? duration : nil,
            readSeconds: readSeconds,
            suggestedTime: hasTime ? TimeOfDay(hour: parts.hour ?? 9, minute: parts.minute ?? 0) : nil
        )
        onSave(task)
        dismiss()
    }
}
