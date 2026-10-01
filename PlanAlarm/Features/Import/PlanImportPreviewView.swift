import SwiftData
import SwiftUI

/// Shows what a plan contains (or what's wrong with it) before it replaces the active plan. If the plan's
/// start date has already passed, asks how to begin it: continue it from today / tomorrow / a date, or
/// start it from day 1 on one of those dates.
struct PlanImportPreviewView: View {
    let pending: PendingImport

    @Environment(ImportController.self) private var importer
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<StoredPlan> { $0.isActive == true }) private var activePlans: [StoredPlan]
    @State private var saveError: String?
    @State private var startChoice: PlanStartChoice?
    private let today = LocalDate.today()

    init(pending: PendingImport) {
        self.pending = pending
        let today = LocalDate.today()
        if let plan = pending.result.plan, PlanStartChoice.isNeeded(for: plan, today: today) {
            _startChoice = State(initialValue: PlanStartChoice(for: plan, today: today))
        }
    }

    private var result: PlanParseResult { pending.result }

    /// The plan as it will be saved (after the start-date choice), or nil if that choice isn't possible.
    private var planToUse: Plan? {
        guard let plan = result.plan else { return nil }
        guard let startChoice else { return plan }
        return startChoice.apply(to: plan, today: today)
    }

    private var canUse: Bool { result.isValid && planToUse != nil }

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

                if let original = result.plan {
                    let plan = planToUse ?? original
                    Section("Plan") {
                        LabeledContent("Name", value: plan.name)
                        LabeledContent("Dates", value: plan.dateRangeText)
                        LabeledContent("Tasks", value: plan.taskCountText)
                        LabeledContent("From", value: pending.sourceName)
                    }

                    if startChoice != nil {
                        startSection(original)
                    } else if let note = plan.timingNote(today: today) {
                        Section {
                            Label(note, systemImage: "info.circle")
                        }
                    }

                    if let current = activePlans.first {
                        Section {
                            Label("Replaces “\(current.name)”. It will be archived. Days you've already checked in, and today if it's locked in, keep their tasks.",
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
                    .disabled(!canUse)
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

    @ViewBuilder
    private func startSection(_ original: Plan) -> some View {
        let daysAgo = original.startDate.days(until: today)
        Section {
            Label("This plan started on \(original.startDate.mediumText), \(daysAgo == 1 ? "yesterday" : "\(daysAgo) days ago").",
                  systemImage: "calendar.badge.exclamationmark")
                .foregroundStyle(.orange)

            Picker("How to start", selection: modeBinding) {
                Text("Continue it").tag(PlanStartChoice.Mode.continuePlan)
                Text("Start from day 1").tag(PlanStartChoice.Mode.restartFromDayOne)
            }
            .pickerStyle(.segmented)

            Picker("Starting", selection: dayBinding) {
                Text("Today").tag(PlanStartChoice.Day.today)
                Text("Tomorrow").tag(PlanStartChoice.Day.tomorrow)
                Text("Pick a date").tag(PlanStartChoice.Day.other)
            }
            .pickerStyle(.segmented)

            if startChoice?.day == .other {
                DatePicker("Date", selection: otherDateBinding, in: today.date()..., displayedComponents: .date)
                    .environment(\.calendar, .plan)
            }

            if planToUse == nil, let end = original.endDate {
                Label("The plan ends on \(end.mediumText), before that date. Choose “Start from day 1”, or an earlier date.",
                      systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Start date")
        } footer: {
            Text(startExplanation(original))
        }
    }

    private func startExplanation(_ original: Plan) -> String {
        guard let startChoice else { return "" }
        let start = startChoice.startDate(today: today).mediumText
        switch startChoice.mode {
        case .continuePlan:
            return "Continue it: from \(start), each day follows the plan as written; the plan days before it are skipped."
        case .restartFromDayOne:
            let end = planToUse?.endDate.map { ", and now ends on \($0.mediumText)" } ?? ""
            return "Start from day 1: the whole plan moves so its first day is \(start)\(end). Your weekly routine stays on the same weekdays; date-specific changes move with the plan."
        }
    }

    private var modeBinding: Binding<PlanStartChoice.Mode> {
        Binding(get: { startChoice?.mode ?? .continuePlan }, set: { startChoice?.mode = $0 })
    }

    private var dayBinding: Binding<PlanStartChoice.Day> {
        Binding(get: { startChoice?.day ?? .today }, set: { startChoice?.day = $0 })
    }

    private var otherDateBinding: Binding<Date> {
        Binding(get: { (startChoice?.otherDate ?? today).date() }, set: { startChoice?.otherDate = LocalDate($0) })
    }

    private func confirm() {
        guard let plan = planToUse else { return }
        do {
            try importer.confirm(pending, plan: plan, in: modelContext)
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
