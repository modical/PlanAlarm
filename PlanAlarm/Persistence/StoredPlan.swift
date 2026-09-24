import Foundation
import SwiftData

/// An imported plan. Exactly one is active; replaced plans stay as archived records (never deleted).
/// The original JSON is stored and re-parsed on demand, so the stored shape never depends on `Plan`'s.
@Model
final class StoredPlan {
    var id: UUID = UUID()
    var name: String = ""
    /// Where it came from: a file name, "Pasted text" or "Sample plan".
    var sourceName: String = ""
    var importedAt: Date = Date.now
    var isActive: Bool = false
    /// "YYYY-MM-DD"
    var startDate: String = ""
    var endDate: String?
    var json: Data = Data()

    init(plan: Plan, json: Data, sourceName: String, isActive: Bool, importedAt: Date = .now) {
        self.id = UUID()
        self.name = plan.name
        self.sourceName = sourceName
        self.importedAt = importedAt
        self.isActive = isActive
        self.startDate = plan.startDate.description
        self.endDate = plan.endDate?.description
        self.json = json
    }
}
