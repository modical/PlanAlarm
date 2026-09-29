import Foundation
import SwiftData

/// A task the user added in the app on a date the plan doesn't cover (outside its dates, or with no
/// plan loaded). Kept outside the plan file so the schema stays unchanged, so it survives plan
/// replacement but isn't included when a plan is shared.
@Model
final class ExtraTask {
    var id: UUID = UUID()
    /// "YYYY-MM-DD"
    var date: String = ""
    /// JSON-encoded `PlanTask`.
    var taskJSON: Data = Data()
    var createdAt: Date = Date.now

    init(date: LocalDate, task: PlanTask) {
        self.id = UUID()
        self.date = date.description
        self.taskJSON = (try? JSONEncoder().encode(task)) ?? Data()
        self.createdAt = .now
    }

    var task: PlanTask? {
        try? JSONDecoder().decode(PlanTask.self, from: taskJSON)
    }
}

@MainActor
enum ExtraTaskStore {
    static func add(_ task: PlanTask, on date: LocalDate, in context: ModelContext) throws {
        context.insert(ExtraTask(date: date, task: task))
        try context.save()
    }

    static func update(_ extra: ExtraTask, with task: PlanTask, in context: ModelContext) throws {
        extra.taskJSON = try JSONEncoder().encode(task)
        try context.save()
    }

    static func delete(_ extras: [ExtraTask], in context: ModelContext) throws {
        for extra in extras {
            context.delete(extra)
        }
        try context.save()
    }
}

/// One day's tasks: the plan's tasks first, then the user's extra tasks for that date.
struct DayAgenda: Identifiable {
    let day: ResolvedDay
    /// How many of `day.tasks` come from the plan; the rest are `extras`, in order.
    let planTaskCount: Int
    let extras: [ExtraTask]

    var id: LocalDate { day.date }

    @MainActor
    init(date: LocalDate, plan: Plan?, extras allExtras: [ExtraTask]) {
        var day = plan?.day(on: date)
            ?? ResolvedDay(date: date, isInPlan: false, dayNote: nil, tasks: [], overrideMode: nil)
        let mine = allExtras
            .filter { $0.date == date.description && $0.task != nil }
            .sorted { $0.createdAt < $1.createdAt }
        planTaskCount = day.tasks.count
        day.tasks += mine.compactMap(\.task)
        self.day = day
        self.extras = mine
    }

    /// The extra task at a position in `day.tasks`, if that task is an extra.
    func extra(at index: Int) -> ExtraTask? {
        let position = index - planTaskCount
        return extras.indices.contains(position) ? extras[position] : nil
    }
}
