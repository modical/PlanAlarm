import CoreTransferable
import Foundation
import SwiftData
import UniformTypeIdentifiers

/// The history backup file (JSON): every locked-in day and every task record, with statuses and times.
struct HistoryExport: Codable, Sendable {
    struct Day: Codable, Sendable {
        var date: String
        var dayNote: String?
        var planName: String?
        var lockedInAt: Date?
        var tasks: [TaskEntry]
    }

    struct TaskEntry: Codable, Sendable {
        var title: String
        var category: String
        var status: String
        var addedInApp: Bool
        var scheduledFor: Date?
        var ringingAt: Date?
        var startedAt: Date?
        var doneAt: Date?
        var skippedAt: Date?
        var snoozeCount: Int
        var details: PlanTask?
    }

    var app = "PlanAlarm"
    var formatVersion = 1
    var exportedAt: Date
    var days: [Day]

    @MainActor
    init(dayRecords: [DayRecord], taskRecords: [TaskRecord], exportedAt: Date = .now) {
        self.exportedAt = exportedAt
        let dayInfo = Dictionary(dayRecords.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        let tasksByDate = Dictionary(grouping: taskRecords, by: \.date)
        let dates = Set(dayInfo.keys).union(tasksByDate.keys).sorted()
        days = dates.map { date in
            let info = dayInfo[date]
            let tasks = (tasksByDate[date] ?? []).sorted { $0.order < $1.order }.map { record in
                TaskEntry(title: record.title, category: record.category, status: record.status.rawValue,
                     addedInApp: record.isExtra, scheduledFor: record.scheduledFor, ringingAt: record.ringingAt,
                     startedAt: record.startedAt, doneAt: record.doneAt, skippedAt: record.skippedAt,
                     snoozeCount: record.snoozeCount, details: record.task)
            }
            return Day(date: date, dayNote: info?.dayNote, planName: info?.planName, lockedInAt: info?.lockedInAt, tasks: tasks)
        }
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> HistoryExport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(HistoryExport.self, from: data)
    }
}

/// The export shared through the share sheet as a .json file.
/// The export shared through the share sheet as a .json file. The file is built only when it's actually
/// shared, not every time a screen showing the Export button is drawn.
struct HistoryExportFile: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { _ in
            let (fileName, data) = try await MainActor.run { try makeFile() }
            let url = URL.temporaryDirectory.appending(path: fileName)
            try data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }

    @MainActor
    static func makeFile(context: ModelContext = AppDatabase.context, now: Date = .now) throws -> (String, Data) {
        let days = try context.fetch(FetchDescriptor<DayRecord>())
        let tasks = try context.fetch(FetchDescriptor<TaskRecord>())
        let data = try HistoryExport(dayRecords: days, taskRecords: tasks, exportedAt: now).encoded()
        return ("PlanAlarm-history-\(LocalDate(now).description).json", data)
    }
}

extension HistoryDay {
    /// History days built from stored records: every date with a check-in or task records.
    @MainActor
    static func days(dayRecords: [DayRecord], taskRecords: [TaskRecord]) -> [LocalDate: HistoryDay] {
        var result: [LocalDate: HistoryDay] = [:]
        for day in dayRecords {
            guard let date = LocalDate(isoString: day.date) else { continue }
            result[date] = HistoryDay(date: date, tasks: [], checkedIn: day.checkedIn)
        }
        for record in taskRecords.sorted(by: { $0.order < $1.order }) {
            guard let date = LocalDate(isoString: record.date) else { continue }
            result[date, default: HistoryDay(date: date, tasks: [])].tasks
                .append(HistoryTask(title: record.title, category: record.category, status: record.status))
        }
        return result
    }
}
