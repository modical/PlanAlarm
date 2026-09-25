import Foundation

/// Writes a `Plan` back to schema-v1 JSON (used for in-app edits and new plans).
/// `PlanParser.parse(PlanEncoder.encode(plan)).plan == plan` always holds.
enum PlanEncoder {
    static func encode(_ plan: Plan) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(jsonValue(for: plan))
    }

    static func jsonValue(for plan: Plan) -> JSONValue {
        var root: [String: JSONValue] = [
            "schemaVersion": .number(Double(Plan.supportedSchemaVersion)),
            "planName": .string(plan.name),
            "startDate": .string(plan.startDate.description),
            "defaults": .object(["readSeconds": .number(Double(plan.defaultReadSeconds))]),
        ]
        if let endDate = plan.endDate {
            root["endDate"] = .string(endDate.description)
        }
        if !plan.library.isEmpty {
            root["taskLibrary"] = .object(plan.library.mapValues { .object(fields(of: $0, base: nil, plan: plan)) })
        }
        if !plan.weeklyTemplate.isEmpty {
            var weekly: [String: JSONValue] = [:]
            for (weekday, day) in plan.weeklyTemplate {
                weekly[weekday.rawValue] = .object(dayObject(note: day.dayNote, tasks: day.tasks, plan: plan))
            }
            root["weeklyTemplate"] = .object(weekly)
        }
        if !plan.dateOverrides.isEmpty {
            var overrides: [String: JSONValue] = [:]
            for (date, override) in plan.dateOverrides {
                var obj = dayObject(note: override.dayNote, tasks: override.tasks, plan: plan)
                obj["mode"] = .string(override.mode.rawValue)
                overrides[date.description] = .object(obj)
            }
            root["dateOverrides"] = .object(overrides)
        }
        return .object(root)
    }

    private static func dayObject(note: String?, tasks: [PlanTask], plan: Plan) -> [String: JSONValue] {
        var obj: [String: JSONValue] = ["tasks": .array(tasks.map { entry(for: $0, plan: plan) })]
        if let note { obj["dayNote"] = .string(note) }
        return obj
    }

    /// A taskRef plus only the fields that differ from the library entry, or a full inline task.
    private static func entry(for task: PlanTask, plan: Plan) -> JSONValue {
        if let ref = task.taskRef, let base = plan.library[ref] {
            var obj = fields(of: task, base: base, plan: plan)
            obj["taskRef"] = .string(ref)
            return .object(obj)
        }
        return .object(fields(of: task, base: nil, plan: plan))
    }

    private static func fields(of task: PlanTask, base: PlanTask?, plan: Plan) -> [String: JSONValue] {
        var obj: [String: JSONValue] = [:]
        if task.title != base?.title { obj["title"] = .string(task.title) }
        if task.category != base?.category { obj["category"] = .string(task.category) }
        if let duration = task.durationMinutes, duration != base?.durationMinutes {
            obj["durationMinutes"] = .number(Double(duration))
        }
        if task.readSeconds != (base?.readSeconds ?? plan.defaultReadSeconds) {
            obj["readSeconds"] = .number(Double(task.readSeconds))
        }
        if let time = task.suggestedTime, time != base?.suggestedTime {
            obj["suggestedTime"] = .string(time.description)
        }

        var description: [String: JSONValue] = [:]
        if let summary = task.summary, summary != base?.summary {
            description["summary"] = .string(summary)
        }
        if task.sections != (base?.sections ?? []) {
            description["sections"] = .array(task.sections.map { section in
                .object(["title": .string(section.title), "items": .array(section.items.map { .string($0) })])
            })
        }
        if !description.isEmpty {
            obj["description"] = .object(description)
        }
        return obj
    }
}
