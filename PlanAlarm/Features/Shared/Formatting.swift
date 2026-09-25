import Foundation

extension LocalDate {
    /// Formats this day with the Gregorian calendar in the device's time zone.
    func formatted(_ style: Date.FormatStyle) -> String {
        var style = style
        style.calendar = .plan
        style.timeZone = .current
        return date().formatted(style)
    }

    /// "Thu, Oct 1"
    var shortText: String { formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }
    /// "Thursday, October 1"
    var longText: String { formatted(.dateTime.weekday(.wide).month(.wide).day()) }
    /// "Oct 1, 2026"
    var mediumText: String { formatted(.dateTime.month(.abbreviated).day().year()) }
    /// "Oct 1"
    var monthDayText: String { formatted(.dateTime.month(.abbreviated).day()) }
}

extension LocalDate: Identifiable {
    var id: LocalDate { self }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension Plan {
    var dateRangeText: String {
        if let endDate {
            "\(startDate.mediumText) – \(endDate.mediumText)"
        } else {
            "From \(startDate.mediumText), no end date"
        }
    }

    var taskCountText: String {
        let library = "\(library.count) in library"
        if let total = totalScheduledTasks {
            return "\(total) scheduled · \(library)"
        }
        return "\(tasksPerTemplateWeek) per week · \(library)"
    }

    /// A note when today is outside the plan's dates.
    func timingNote(today: LocalDate) -> String? {
        if let endDate, endDate < today {
            return "This plan ended on \(endDate.mediumText). Days after that have no tasks."
        }
        if startDate > today {
            return "This plan starts on \(startDate.mediumText). Until then there are no tasks."
        }
        return nil
    }
}

extension PlanTask {
    /// "45 min", "1 h", "1 h 15 min"
    var durationText: String? {
        guard let minutes = durationMinutes else { return nil }
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }
}
