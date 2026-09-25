import SwiftUI

/// What the editor sheet is doing: adding a task to a date, or editing the task at `index`.
struct TaskEditRequest: Identifiable {
    let id = UUID()
    let date: LocalDate
    /// The task's position on the date when editing; nil when adding.
    let index: Int?
    let existing: PlanTask?
    /// Whether "every week" is offered (adding, or editing a task from the weekly pattern).
    let allowsEveryWeek: Bool

    static func add(on date: LocalDate) -> TaskEditRequest {
        TaskEditRequest(date: date, index: nil, existing: nil, allowsEveryWeek: true)
    }
}

/// Adds or edits a task for one date or for every week. Tasks are saved as complete inline
/// tasks, so later library changes don't alter them.
struct TaskEditorView: View {
    let request: TaskEditRequest
    let plan: Plan
    let onSave: (PlanTask, EditScope) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var scope: EditScope = .thisDate
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

    init(request: TaskEditRequest, plan: Plan, onSave: @escaping (PlanTask, EditScope) -> Void) {
        self.request = request
        self.plan = plan
        self.onSave = onSave
        _readSeconds = State(initialValue: plan.defaultReadSeconds)
        _time = State(initialValue: request.date.date(hour: 9, minute: 0))
    }

    private var isEditing: Bool { request.existing != nil }
    private var date: LocalDate { request.date }

    private var categorySuggestions: [String] {
        let fromPlan = plan.library.values.map(\.category)
        return Array(Set(["gym", "mobility", "study", "nutrition", "other"] + fromPlan)).sorted()
    }

    private var canSave: Bool {
        !title.trimmed.isEmpty && !category.trimmed.isEmpty
    }

    private var scopeNote: String {
        switch scope {
        case .thisDate:
            "Only \(date.longText) changes."
        case .everyWeek:
            "Every \(date.weekday.displayName) in the plan changes, except dates you changed one by one."
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if request.allowsEveryWeek {
                        Picker("Applies to", selection: $scope) {
                            Text("Only \(date.shortText)").tag(EditScope.thisDate)
                            Text("Every \(date.weekday.displayName)").tag(EditScope.everyWeek)
                        }
                        .pickerStyle(.segmented)
                    }
                    Text(scopeNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if !isEditing && !plan.library.isEmpty {
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
            .navigationTitle(isEditing ? "Edit Task" : "Add Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if let existing = request.existing { fill(from: existing) }
            }
            .onChange(of: libraryKey) {
                if let libraryKey, let task = plan.library[libraryKey] { fill(from: task) }
            }
        }
    }

    private func fill(from task: PlanTask) {
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
        onSave(task, request.allowsEveryWeek ? scope : .thisDate)
        dismiss()
    }
}
