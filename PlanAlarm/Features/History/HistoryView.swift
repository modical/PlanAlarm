import SwiftData
import SwiftUI

/// History: a month calendar coloured by how each day went, streaks, and completion rates.
struct HistoryView: View {
    @Query private var dayRecords: [DayRecord]
    @Query private var taskRecords: [TaskRecord]
    @State private var month: (year: Int, month: Int) = {
        let today = LocalDate.today()
        return (today.year, today.month)
    }()
    @State private var selectedDate: LocalDate?

    private var today: LocalDate { .today() }
    private var days: [LocalDate: HistoryDay] { HistoryDay.days(dayRecords: dayRecords, taskRecords: taskRecords) }

    var body: some View {
        NavigationStack {
            let historyDays = days
            List {
                Section {
                    MonthCalendar(year: month.year, month: month.month, days: historyDays, today: today) { date in
                        selectedDate = date
                    } onChangeMonth: { delta in
                        changeMonth(by: delta)
                    }
                    CalendarLegend()
                }

                if historyDays.isEmpty {
                    Section {
                        Text("Your history starts with your first morning check-in.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    StreaksSection(days: historyDays, today: today)
                    CompletionSection(days: historyDays, today: today)
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: HistoryExportFile(), preview: SharePreview("PlanAlarm history")) {
                        Label("Export History", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .sheet(item: $selectedDate) { date in
                DayHistoryView(date: date, kind: HistoryCalculator.kind(on: date, days: historyDays, today: today))
            }
        }
    }

    private func changeMonth(by delta: Int) {
        var year = month.year
        var value = month.month + delta
        while value < 1 { value += 12; year -= 1 }
        while value > 12 { value -= 12; year += 1 }
        month = (year, value)
    }
}

// MARK: - Calendar

private struct MonthCalendar: View {
    let year: Int
    let month: Int
    let days: [LocalDate: HistoryDay]
    let today: LocalDate
    let onSelect: (LocalDate) -> Void
    let onChangeMonth: (Int) -> Void

    private let firstWeekday = Calendar.plan.firstWeekday

    /// The month in rows of 7. Plain stacks (not a lazy grid): lazy grids inside a List row made
    /// UIKit's list layout loop and crash (seen on a 440-point-wide iPhone, reproduced in CI).
    private var weeks: [[LocalDate?]] {
        let cells = HistoryCalculator.monthGrid(year: year, month: month, firstWeekday: firstWeekday)
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
    }

    private var title: String {
        LocalDate(year: year, month: month, day: 1)?.formatted(.dateTime.month(.wide).year()) ?? ""
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button("Previous month", systemImage: "chevron.left") { onChangeMonth(-1) }
                    .labelStyle(.iconOnly)
                Spacer()
                Text(title).font(.headline)
                Spacer()
                Button("Next month", systemImage: "chevron.right") { onChangeMonth(1) }
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .imageScale(.large)

            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    ForEach(Weekday.ordered(firstWeekday: firstWeekday), id: \.self) { weekday in
                        Text(weekday.displayName.prefix(3))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    HStack(spacing: 4) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, date in
                            if let date {
                                DayCell(date: date, kind: HistoryCalculator.kind(on: date, days: days, today: today),
                                        isToday: date == today)
                                    .onTapGesture { onSelect(date) }
                            } else {
                                Color.clear.frame(maxWidth: .infinity).frame(height: 36)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct DayCell: View {
    let date: LocalDate
    let kind: DayKind
    let isToday: Bool

    var body: some View {
        Text("\(date.day)")
            .font(.subheadline.weight(isToday ? .bold : .regular))
            .monospacedDigit()
            .foregroundStyle(kind.usesLightText ? Color.white : Color.primary)
            .frame(width: 36, height: 36)
            .background(kind.color, in: Circle())
            .overlay {
                if isToday {
                    Circle().strokeBorder(Color.primary, lineWidth: 2)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .accessibilityLabel("\(date.longText): \(kind.label)")
            .accessibilityAddTraits(.isButton)
    }
}

private struct CalendarLegend: View {
    private let kinds: [DayKind] = [.allDone, .partial, .noneDone, .restDay, .inProgress, .missed]

    /// Two fixed columns (plain stacks, see `MonthCalendar.weeks`).
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(stride(from: 0, to: kinds.count, by: 2)), id: \.self) { index in
                HStack(spacing: 12) {
                    item(kinds[index])
                    if index + 1 < kinds.count {
                        item(kinds[index + 1])
                    }
                }
            }
        }
    }

    private func item(_ kind: DayKind) -> some View {
        HStack(spacing: 6) {
            Circle().fill(kind.color).frame(width: 12, height: 12)
            Text(kind.label).font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension DayKind {
    var color: Color {
        switch self {
        case .allDone: .green
        case .partial: .orange
        case .noneDone: .red
        case .restDay: Color.gray.opacity(0.25)
        case .inProgress: Color.blue.opacity(0.3)
        case .missed: Color.red.opacity(0.25)
        case .noData: .clear
        }
    }

    var usesLightText: Bool {
        self == .allDone || self == .partial || self == .noneDone
    }

    var label: String {
        switch self {
        case .allDone: "All done"
        case .partial: "Partly done"
        case .noneDone: "Nothing done"
        case .restDay: "Rest day"
        case .inProgress: "Today, in progress"
        case .missed: "No check-in"
        case .noData: "No data"
        }
    }
}

// MARK: - Streaks and completion

private struct StreaksSection: View {
    let days: [LocalDate: HistoryDay]
    let today: LocalDate

    var body: some View {
        let perfect = HistoryCalculator.perfectDayStreak(days: days, today: today)
        let categories = HistoryCalculator.categoryStreaks(days: days, today: today).sorted { $0.key < $1.key }
        Section {
            StreakRow(title: "Perfect days", systemImage: "star.fill", streak: perfect)
            ForEach(categories, id: \.key) { entry in
                StreakRow(title: entry.key.capitalized, systemImage: "flame.fill", streak: entry.value)
            }
        } header: {
            Text("Streaks")
        } footer: {
            Text("A perfect day has every task done. Skipped or unlogged tasks and days without a check-in break it; rest days don't. Today counts once it's complete.")
        }
    }
}

private struct StreakRow: View {
    let title: String
    let systemImage: String
    let streak: Streak

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(streak.current) \(streak.current == 1 ? "day" : "days")")
                    .font(.headline)
                    .monospacedDigit()
                Text("best \(streak.best)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

private struct CompletionSection: View {
    let days: [LocalDate: HistoryDay]
    let today: LocalDate

    var body: some View {
        let week = HistoryCalculator.completion(days: days, today: today, window: 7)
        let month = HistoryCalculator.completion(days: days, today: today, window: 30)
        let categories = Set(week.byCategory.keys).union(month.byCategory.keys).sorted()
        Section {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    Text("")
                    Text("7 days").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text("30 days").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                GridRow {
                    Text("All tasks").font(.headline)
                    CompletionText(completion: week.overall)
                    CompletionText(completion: month.overall)
                }
                ForEach(categories, id: \.self) { category in
                    GridRow {
                        Text(category.capitalized)
                        CompletionText(completion: week.byCategory[category] ?? Completion())
                        CompletionText(completion: month.byCategory[category] ?? Completion())
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Completion")
        } footer: {
            Text("Tasks done out of tasks due. Today's open tasks aren't counted yet.")
        }
    }
}

private struct CompletionText: View {
    let completion: Completion

    var body: some View {
        if let fraction = completion.fraction {
            VStack(alignment: .leading, spacing: 0) {
                Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                    .monospacedDigit()
                Text("\(completion.done)/\(completion.total)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }
}

// MARK: - One day

private struct DayHistoryView: View {
    let date: LocalDate
    let kind: DayKind

    @Query private var records: [TaskRecord]
    @Query private var dayRecords: [DayRecord]
    @Environment(\.dismiss) private var dismiss

    init(date: LocalDate, kind: DayKind) {
        self.date = date
        self.kind = kind
        let key = date.description
        _records = Query(filter: #Predicate<TaskRecord> { $0.date == key }, sort: \TaskRecord.order)
        _dayRecords = Query(filter: #Predicate<DayRecord> { $0.date == key })
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(kind.label, systemImage: "circle.fill")
                        .foregroundStyle(kind == .noData ? Color.secondary : kind.color)
                    if let day = dayRecords.first {
                        if let note = day.dayNote {
                            Text(note).foregroundStyle(.secondary)
                        }
                        if let plan = day.planName {
                            LabeledContent("Plan", value: plan)
                        }
                        LabeledContent("Locked in", value: day.lockedInAt.formatted(date: .omitted, time: .shortened))
                    }
                }
                Section("Tasks") {
                    if records.isEmpty {
                        Text(kind == .restDay ? "Rest day: no tasks." : "No tasks recorded.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(records.sorted { ($0.scheduledFor ?? .distantFuture) < ($1.scheduledFor ?? .distantFuture) }) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(record.title).font(.headline)
                                Spacer()
                                StatusChip(status: record.status)
                            }
                            Text(details(for: record))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func details(for record: TaskRecord) -> String {
        var parts = [record.category]
        if let time = record.scheduledFor {
            parts.append("alarm \(time.formatted(date: .omitted, time: .shortened))")
        }
        if record.snoozeCount > 0 {
            parts.append("rang again \(record.snoozeCount)×")
        }
        if let started = record.startedAt {
            parts.append("started \(started.formatted(date: .omitted, time: .shortened))")
        }
        if let done = record.doneAt {
            parts.append("done \(done.formatted(date: .omitted, time: .shortened))")
        }
        return parts.joined(separator: " · ")
    }
}
