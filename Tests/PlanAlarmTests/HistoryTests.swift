import Foundation
import SwiftData
import Testing
@testable import PlanAlarm

struct HistoryCalculatorTests {
    private let date = Fixtures.date

    private func task(_ category: String, _ status: TaskStatus, _ title: String = "Task") -> HistoryTask {
        HistoryTask(title: title, category: category, status: status)
    }

    /// Builds history from (date, tasks) pairs; an empty task list is a rest day.
    private func history(_ entries: [(String, [HistoryTask])]) -> [LocalDate: HistoryDay] {
        Dictionary(uniqueKeysWithValues: entries.map { (date($0.0), HistoryDay(date: date($0.0), tasks: $0.1)) })
    }

    // MARK: Day kinds

    @Test func dayKinds() {
        let days = history([
            ("2026-10-01", [task("gym", .done), task("study", .done)]),
            ("2026-10-02", [task("gym", .done), task("study", .skipped)]),
            ("2026-10-03", [task("gym", .unlogged)]),
            ("2026-10-04", []),
            ("2026-10-06", [task("gym", .done), task("study", .scheduled)]),
        ])
        let today = date("2026-10-06")
        #expect(HistoryCalculator.kind(on: date("2026-10-01"), days: days, today: today) == .allDone)
        #expect(HistoryCalculator.kind(on: date("2026-10-02"), days: days, today: today) == .partial)
        #expect(HistoryCalculator.kind(on: date("2026-10-03"), days: days, today: today) == .noneDone)
        #expect(HistoryCalculator.kind(on: date("2026-10-04"), days: days, today: today) == .restDay)
        #expect(HistoryCalculator.kind(on: date("2026-10-05"), days: days, today: today) == .missed)
        #expect(HistoryCalculator.kind(on: date("2026-10-06"), days: days, today: today) == .inProgress)
        #expect(HistoryCalculator.kind(on: date("2026-09-30"), days: days, today: today) == .noData) // before first use
        #expect(HistoryCalculator.kind(on: date("2026-10-07"), days: days, today: today) == .noData) // future
    }

    // MARK: Perfect-day streak

    @Test func restDaysNeitherBreakNorExtend() {
        let days = history([
            ("2026-10-01", [task("gym", .done)]),
            ("2026-10-02", []),
            ("2026-10-03", [task("gym", .done)]),
            ("2026-10-04", []),
        ])
        #expect(HistoryCalculator.perfectDayStreak(days: days, today: date("2026-10-04")) == Streak(current: 2, best: 2))
    }

    @Test func skipsUnloggedAndMissedDaysBreak() {
        let skipped = history([("2026-10-01", [task("gym", .done)]), ("2026-10-02", [task("gym", .skipped)]),
                               ("2026-10-03", [task("gym", .done)])])
        #expect(HistoryCalculator.perfectDayStreak(days: skipped, today: date("2026-10-03")) == Streak(current: 1, best: 1))

        let unlogged = history([("2026-10-01", [task("gym", .done)]), ("2026-10-02", [task("gym", .done), task("x", .unlogged)])])
        #expect(HistoryCalculator.perfectDayStreak(days: unlogged, today: date("2026-10-03")).current == 0)

        let missed = history([("2026-10-01", [task("gym", .done)]), ("2026-10-03", [task("gym", .done)])])
        #expect(HistoryCalculator.perfectDayStreak(days: missed, today: date("2026-10-03")) == Streak(current: 1, best: 1))
    }

    @Test func todayCountsOnlyWhenComplete() {
        var days = history([("2026-10-01", [task("gym", .done)]), ("2026-10-02", [task("gym", .done), task("study", .scheduled)])])
        let today = date("2026-10-02")
        #expect(HistoryCalculator.perfectDayStreak(days: days, today: today) == Streak(current: 1, best: 1)) // not broken yet
        days[today]?.tasks[1].status = .done
        #expect(HistoryCalculator.perfectDayStreak(days: days, today: today) == Streak(current: 2, best: 2))
        days[today]?.tasks[1].status = .skipped
        #expect(HistoryCalculator.perfectDayStreak(days: days, today: today) == Streak(current: 0, best: 1))
    }

    @Test func notCheckingInTodayDoesNotBreakTheStreak() {
        let days = history([("2026-10-01", [task("gym", .done)]), ("2026-10-02", [task("gym", .done)])])
        #expect(HistoryCalculator.perfectDayStreak(days: days, today: date("2026-10-03")).current == 2)
    }

    @Test func bestStreakIsRemembered() {
        let days = history([
            ("2026-10-01", [task("gym", .done)]), ("2026-10-02", [task("gym", .done)]), ("2026-10-03", [task("gym", .done)]),
            ("2026-10-04", [task("gym", .skipped)]),
            ("2026-10-05", [task("gym", .done)]),
        ])
        #expect(HistoryCalculator.perfectDayStreak(days: days, today: date("2026-10-05")) == Streak(current: 1, best: 3))
    }

    @Test func streaksCrossCairoDSTDays() {
        // 24 Apr 2026 (23 hours) and 29 Oct 2026 (25 hours) are ordinary days in the streak.
        let spring = (21...27).map { day -> (String, [HistoryTask]) in
            (String(format: "2026-04-%02d", day), [task("gym", .done)])
        }
        #expect(HistoryCalculator.perfectDayStreak(days: history(spring), today: date("2026-04-27")) == Streak(current: 7, best: 7))
        let autumn = (27...31).map { day -> (String, [HistoryTask]) in
            (String(format: "2026-10-%02d", day), [task("gym", .done)])
        } + [("2026-11-01", [task("gym", .done)])]
        #expect(HistoryCalculator.perfectDayStreak(days: history(autumn), today: date("2026-11-01")) == Streak(current: 6, best: 6))
    }

    // MARK: Category streaks

    @Test func categoryStreaksIgnoreDaysWithoutTheCategory() {
        let days = history([
            ("2026-10-01", [task("gym", .done), task("study", .done)]),
            ("2026-10-02", [task("study", .skipped)]),              // no gym: ignored for gym
            ("2026-10-03", [task("Gym", .done)]),                   // same category, different case
            ("2026-10-04", []),                                     // rest day
            ("2026-10-05", [task("gym ", .done), task("study", .done)]),
        ])
        let streaks = HistoryCalculator.categoryStreaks(days: days, today: date("2026-10-05"))
        #expect(streaks["gym"] == Streak(current: 3, best: 3))
        #expect(streaks["study"] == Streak(current: 1, best: 1))
    }

    @Test func categoryStreakBreaksOnlyOnItsOwnTasks() {
        let days = history([
            ("2026-10-01", [task("gym", .done), task("gym", .done, "Stretch")]),
            ("2026-10-02", [task("gym", .done), task("gym", .unlogged, "Stretch")]),
            ("2026-10-03", [task("gym", .done)]),
        ])
        #expect(HistoryCalculator.categoryStreaks(days: days, today: date("2026-10-03"))["gym"] == Streak(current: 1, best: 1))
    }

    @Test func categoryStreaksSurvivePlanChanges() {
        // Different plans (different task titles) on consecutive days; the category carries on.
        let days = history([
            ("2026-10-30", [task("gym", .done, "Gym — Push day (October Cut)")]),
            ("2026-10-31", [task("gym", .done, "Gym — Light legs (deload)")]),
            ("2026-11-01", [task("gym", .done, "Gym — Full body (November Bulk)")]),
        ])
        #expect(HistoryCalculator.categoryStreaks(days: days, today: date("2026-11-01"))["gym"]?.current == 3)
        #expect(HistoryCalculator.perfectDayStreak(days: days, today: date("2026-11-01")).current == 3)
    }

    @Test func categoryTodayWaitsUntilDone() {
        let days = history([("2026-10-01", [task("gym", .done)]), ("2026-10-02", [task("gym", .inProgress)])])
        #expect(HistoryCalculator.categoryStreaks(days: days, today: date("2026-10-02"))["gym"]?.current == 1)
    }

    // MARK: Completion

    @Test func completionWindows() {
        let days = history([
            ("2026-09-20", [task("gym", .done), task("gym", .done)]),                // outside 7, inside 30
            ("2026-10-01", [task("gym", .done), task("study", .skipped)]),
            ("2026-10-02", [task("study", .done), task("study", .unlogged)]),
            ("2026-10-03", [task("gym", .done), task("study", .scheduled)]),         // today: open task not due yet
        ])
        let today = date("2026-10-03")
        let week = HistoryCalculator.completion(days: days, today: today, window: 7)
        #expect(week.overall == Completion(done: 3, total: 5))
        #expect(week.byCategory["gym"] == Completion(done: 2, total: 2))
        #expect(week.byCategory["study"] == Completion(done: 1, total: 3))
        let month = HistoryCalculator.completion(days: days, today: today, window: 30)
        #expect(month.overall == Completion(done: 5, total: 7))
        #expect(HistoryCalculator.completion(days: [:], today: today, window: 7).overall.fraction == nil)
    }

    // MARK: Calendar grid

    @Test func monthGrid() {
        // October 2026 starts on a Thursday.
        let mondayFirst = HistoryCalculator.monthGrid(year: 2026, month: 10, firstWeekday: 2)
        #expect(mondayFirst.prefix(4).map { $0 == nil } == [true, true, true, false])
        #expect(mondayFirst[3] == date("2026-10-01"))
        #expect(mondayFirst.compactMap { $0 }.count == 31)
        #expect(mondayFirst.count % 7 == 0)

        let saturdayFirst = HistoryCalculator.monthGrid(year: 2026, month: 10, firstWeekday: 7)
        #expect(saturdayFirst.firstIndex { $0 != nil } == 5)

        let february = HistoryCalculator.monthGrid(year: 2028, month: 2, firstWeekday: 1)
        #expect(february.compactMap { $0 }.last == date("2028-02-29"))
    }
}

@MainActor
struct HistoryExportTests {
    @Test func exportRoundTripsAndKeepsEveryDay() throws {
        let container = try ModelContainer(for: DayRecord.self, TaskRecord.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let day = Fixtures.date("2026-10-05")
        let task = PlanTask(taskRef: nil, title: "Gym", category: "gym", summary: "Push.", sections: [],
                            durationMinutes: 60, readSeconds: 30, suggestedTime: nil)
        let records = try DayStore.lockIn(date: day, dayNote: "Push day.", planName: "October Cut",
                                          items: [CheckInItem(id: 0, task: task, isExtra: false, time: day.date(hour: 18, minute: 0))],
                                          in: context)
        try DayStore.log(records[0], as: .done, in: context)
        try DayStore.lockIn(date: day.adding(days: 1), dayNote: nil, planName: nil, items: [], in: context)

        let export = HistoryExport(dayRecords: try context.fetch(FetchDescriptor<DayRecord>()),
                                   taskRecords: try context.fetch(FetchDescriptor<TaskRecord>()))
        let decoded = try HistoryExport.decode(try export.encoded())
        #expect(decoded.days.map(\.date) == ["2026-10-05", "2026-10-06"])
        #expect(decoded.days[0].planName == "October Cut")
        #expect(decoded.days[0].tasks.first?.status == "done")
        #expect(decoded.days[0].tasks.first?.details?.summary == "Push.")
        #expect(decoded.days[1].tasks.isEmpty)

        let history = HistoryDay.days(dayRecords: try context.fetch(FetchDescriptor<DayRecord>()),
                                      taskRecords: try context.fetch(FetchDescriptor<TaskRecord>()))
        #expect(HistoryCalculator.kind(on: day, days: history, today: day.adding(days: 2)) == .allDone)
        #expect(HistoryCalculator.kind(on: day.adding(days: 1), days: history, today: day.adding(days: 2)) == .restDay)
    }
}
