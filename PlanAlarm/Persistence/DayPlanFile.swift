import CoreTransferable
import Foundation

/// A stored plan shared as a `.dayplan` file (e.g. back to Claude, or as a backup).
struct DayPlanFile: Transferable {
    let fileName: String
    let data: Data

    @MainActor
    init(_ stored: StoredPlan) {
        let safeName = stored.name
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        fileName = (safeName.isEmpty ? "Plan" : safeName) + ".dayplan"
        data = stored.json
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .dayplan) { file in
            let url = URL.temporaryDirectory.appending(path: file.fileName)
            try file.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
