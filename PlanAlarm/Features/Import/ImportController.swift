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
        case preview(PendingImport)

        var id: String {
            switch self {
            case .paste: "paste"
            case .preview(let pending): pending.id.uuidString
            }
        }
    }

    nonisolated static let sampleResourceName = "sample-october"

    var sheet: Sheet?
    var isShowingFileImporter = false
    var readError: String?
    /// Increments after each successful import, so the UI can react (e.g. switch to the Plan tab).
    private(set) var importCount = 0

    func showFileImporter() {
        sheet = nil
        isShowingFileImporter = true
    }

    func showPaste() {
        sheet = .paste
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

    func loadSample() {
        guard let url = Bundle.main.url(forResource: Self.sampleResourceName, withExtension: "dayplan"),
              let data = try? Data(contentsOf: url) else {
            readError = "The sample plan is missing from the app."
            return
        }
        preview(data, sourceName: "Sample plan")
    }

    func confirm(_ pending: PendingImport, in context: ModelContext) throws {
        guard pending.result.isValid, let plan = pending.result.plan, let json = pending.result.json else { return }
        try PlanStore.activate(plan, json: json, sourceName: pending.sourceName, in: context)
        sheet = nil
        importCount += 1
    }

    private func preview(_ data: Data, sourceName: String) {
        sheet = .preview(PendingImport(sourceName: sourceName, result: PlanParser.parse(data)))
    }
}
