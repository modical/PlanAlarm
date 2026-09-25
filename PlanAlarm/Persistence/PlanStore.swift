import Foundation
import SwiftData

@MainActor
enum PlanStore {
    /// Parsed plans keyed by record, remembered with the JSON they came from (so edits invalidate them).
    private static var parsedPlans: [UUID: (json: Data, plan: Plan)] = [:]

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
        parsedPlans[stored.id] = (json, plan)
    }

    /// Creates a new plan in the app and makes it active.
    static func create(_ plan: Plan, in context: ModelContext) throws {
        try activate(plan, json: try validatedJSON(for: plan), sourceName: "Created in the app", in: context)
    }

    /// Applies an in-app edit and saves the rewritten plan JSON.
    static func update(_ stored: StoredPlan, in context: ModelContext, _ edit: (inout Plan) throws -> Void) throws {
        guard var plan = plan(for: stored) else { throw PlanEditError.unreadablePlan }
        try edit(&plan)
        let json = try validatedJSON(for: plan)
        stored.json = json
        stored.name = plan.name
        stored.startDate = plan.startDate.description
        stored.endDate = plan.endDate?.description
        stored.modifiedAt = .now
        try context.save()
        parsedPlans[stored.id] = (json, plan)
    }

    /// Deletes a plan record. History is stored separately and is not affected.
    static func delete(_ stored: StoredPlan, in context: ModelContext) throws {
        parsedPlans[stored.id] = nil
        context.delete(stored)
        try context.save()
    }

    /// The parsed plan for a stored record (cached until its JSON changes).
    static func plan(for stored: StoredPlan) -> Plan? {
        let json = stored.json
        if let cached = parsedPlans[stored.id], cached.json == json { return cached.plan }
        guard let plan = PlanParser.parse(json).plan else { return nil }
        parsedPlans[stored.id] = (json, plan)
        return plan
    }

    /// Encodes a plan and re-parses it, so a plan the app can't read is never saved.
    private static func validatedJSON(for plan: Plan) throws -> Data {
        let json = try PlanEncoder.encode(plan)
        let check = PlanParser.parse(json)
        guard check.isValid else {
            throw PlanEditError.invalidResult(check.errors.first?.description ?? "unknown problem")
        }
        return json
    }
}
