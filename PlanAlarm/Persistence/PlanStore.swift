import Foundation
import SwiftData

@MainActor
enum PlanStore {
    private static var parsedPlans: [UUID: Plan] = [:]

    /// Makes `plan` the active plan. The previous active plan is archived, not deleted,
    /// so history that refers to it is kept.
    static func activate(_ plan: Plan, json: Data, sourceName: String, in context: ModelContext) throws {
        let active = try context.fetch(FetchDescriptor<StoredPlan>(predicate: #Predicate { $0.isActive == true }))
        for stored in active {
            stored.isActive = false
        }
        let stored = StoredPlan(plan: plan, json: json, sourceName: sourceName, isActive: true)
        context.insert(stored)
        try context.save()
        parsedPlans[stored.id] = plan
    }

    /// The parsed plan for a stored record (cached, since stored JSON never changes).
    static func plan(for stored: StoredPlan) -> Plan? {
        if let cached = parsedPlans[stored.id] { return cached }
        guard let plan = PlanParser.parse(stored.json).plan else { return nil }
        parsedPlans[stored.id] = plan
        return plan
    }
}
