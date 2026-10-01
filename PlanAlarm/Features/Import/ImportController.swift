import Foundation
import Observation
import SwiftData

struct PendingImport: Identifiable {
    let id = UUID()
    /// A file name, "Pasted text" or "Sample plan".
    let sourceName: String
    let result: PlanParseResult
}

/// Drives every way a plan gets in: "Open in PlanAlarm", Files, paste, and the bundled sample.
/// Each route ends at the preview sheet, where the user confirms.
@MainActor
@Observable
final class ImportController {
    enum Sheet: Identifiable {
        case paste
        case newPlan
        case preview(PendingImport)

        var id: String {
            switch self {
            case .paste: "paste"
            case .newPlan: "newPlan"
            case .preview(let pending): pending.id.uuidString
            }
        }
    }

    nonisolated static let sampleResourceName = "sample-october"

    var sheet: Sheet?
    var isShowingFileImporter = false
    var readError: String?
    /// Increments after each successful import or new plan, so the UI can react (e.g. switch to the Plan tab).
    private(set) var importCount = 0

    func showFileImporter() {
        sheet = nil
        isShowingFileImporter = true
    }

    func showPaste() {
        sheet = .paste
    }

    func showNewPlan() {
        sheet = .newPlan
    }

    func create(_ plan: Plan, in context: ModelContext) throws {
        try PlanStore.create(plan, in: context)
        sheet = nil
        importCount += 1
    }

    func importFile(at url: URL) {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            preview(data, sourceName: url.lastPathComponent)
        } catch {
            readError = "Couldn't read “\(url.lastPathComponent)”. \(error.localizedDescription)"
        }
        // "Open in" copies the file into Documents/Inbox; it isn't needed once read.
        if url.pathComponents.contains("Inbox") {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func importText(_ text: String) {
        sheet = .preview(PendingImport(sourceName: "Pasted text", result: PlanParser.parse(text: text)))
    }

    /// The bundled sample plan, moved by whole weeks to cover today (its own dates are fixed).
    func loadSample(today: LocalDate = .today()) {
        guard let url = Bundle.main.url(forResource: Self.sampleResourceName, withExtension: "dayplan"),
              let data = try? Data(contentsOf: url) else {
            readError = "The sample plan is missing from the app."
            return
        }
        if let plan = PlanParser.parse(data).plan, let moved = try? PlanEncoder.encode(plan.movedToCover(today)) {
            preview(moved, sourceName: "Sample plan")
        } else {
            preview(data, sourceName: "Sample plan")
        }
    }

    /// Uses the previewed plan. `plan` is the plan after the start-date choice; if it differs from the file,
    /// the adjusted plan is saved.
    func confirm(_ pending: PendingImport, plan: Plan, in context: ModelContext) throws {
        guard pending.result.isValid, let original = pending.result.plan, let originalJSON = pending.result.json else { return }
        let json = plan == original ? originalJSON : try PlanEncoder.encode(plan)
        try PlanStore.activate(plan, json: json, sourceName: pending.sourceName, in: context)
        sheet = nil
        importCount += 1
    }

    /// Opens an archived plan in the preview, to use it again.
    func reuse(_ stored: StoredPlan) {
        preview(stored.json, sourceName: "Archived plan “\(stored.name)”")
    }

    private func preview(_ data: Data, sourceName: String) {
        sheet = .preview(PendingImport(sourceName: sourceName, result: PlanParser.parse(data)))
    }
}
