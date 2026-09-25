import SwiftUI
import UIKit

struct PastePlanView: View {
    @Environment(ImportController.self) private var importer
    @State private var text = ""

    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.system(.footnote, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 12)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Paste the plan JSON here: tap “Paste from Clipboard” below, or long-press and choose Paste.")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 17)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                .navigationTitle("Paste Plan")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { importer.sheet = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Check") { importer.importText(text) }
                            .disabled(isEmpty)
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button("Paste from Clipboard", systemImage: "doc.on.clipboard") {
                            if let pasted = UIPasteboard.general.string { text = pasted }
                        }
                        .labelStyle(.titleAndIcon)
                    }
                }
        }
    }
}

/// The ways to bring in a plan, shared by the Plan tab and Settings.
struct ImportPlanButtons: View {
    @Environment(ImportController.self) private var importer

    var body: some View {
        Button("Import from Files…", systemImage: "folder") { importer.showFileImporter() }
        Button("Paste Plan JSON…", systemImage: "doc.on.clipboard") { importer.showPaste() }
        Button("New Empty Plan…", systemImage: "square.and.pencil") { importer.showNewPlan() }
        Button("Load Sample Plan", systemImage: "sparkles") { importer.loadSample() }
    }
}
