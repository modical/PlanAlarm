import Foundation

/// Walks a decoded JSON tree, checks it against schema version 1 (see docs/PLAN_FORMAT.md),
/// and builds a `Plan`. Every problem is recorded with its location; unknown fields are ignored.
struct PlanValidator {
    static let readSecondsRange = 1...3600
    static let durationRange = 1...1440

    private var errors: [PlanIssue] = []
    private var warnings: [PlanIssue] = []
    private var defaultReadSeconds = Plan.fallbackReadSeconds
    private var libraryFields: [String: TaskFields] = [:]
    private var resolvedLibrary: [String: PlanTask] = [:]
    private var brokenLibraryKeys: Set<String> = []
    private var usedLibraryKeys: Set<String> = []

    mutating func validate(_ root: JSONValue) -> PlanParseResult {
        guard case .object(let obj) = root else {
            error(nil, "The plan must be a JSON object that starts with { and ends with }.")
            return result(nil)
        }
        guard checkSchemaVersion(obj) else { return result(nil) }

        let name = requiredString(obj, "planName", at: nil)
        let start = requiredDate(obj, "startDate", at: nil)
        let end = optionalDate(obj, "endDate", at: nil)
        if let start, let end, end < start {
            error(nil, "endDate \(end) is before startDate \(start).")
        }

        if let defaults = object(obj, "defaults", at: nil),
           let read = optionalInt(defaults, "readSeconds", in: Self.readSecondsRange, at: "defaults") {
            defaultReadSeconds = read
        }

        if let library = object(obj, "taskLibrary", at: nil) {
            for key in library.keys.sorted() {
                parseLibraryEntry(key, library[key] ?? .null)
            }
        }

        var weekly: [Weekday: DayTemplate] = [:]
        if let template = object(obj, "weeklyTemplate", at: nil) {
            for key in template.keys.sorted() where Weekday(rawValue: key) == nil {
                error("weeklyTemplate", "'\(key)' isn't a weekday. Use lowercase English names: monday, tuesday, wednesday, thursday, friday, saturday, sunday.")
            }
            for weekday in Weekday.allCases {
                guard let value = nonNull(template[weekday.rawValue]),
                      let day = parseDay(value, at: weekday.displayName) else { continue }
                weekly[weekday] = DayTemplate(dayNote: day.note, tasks: day.tasks)
            }
        }

        var overrides: [LocalDate: DateOverride] = [:]
        if let dict = object(obj, "dateOverrides", at: nil) {
            for key in dict.keys.sorted() {
                let loc = "Override \(key)"
                guard let date = LocalDate(isoString: key) else {
                    error("dateOverrides", "'\(key)' isn't a valid date. Use YYYY-MM-DD, like \"2026-10-06\".")
                    continue
                }
                guard let value = nonNull(dict[key]) else { continue }
                guard case .object(let overrideObj) = value else {
                    typeError(loc, nil, expected: "an object { … }", found: value)
                    continue
                }
                let mode = parseMode(overrideObj, at: loc)
                guard let day = parseDay(value, at: loc), let mode else { continue }
                overrides[date] = DateOverride(mode: mode, dayNote: day.note, tasks: day.tasks)
                if let start, date < start || (end.map { date > $0 } ?? false) {
                    warning(loc, "this date is outside the plan's dates, so the override will be ignored.")
                }
            }
        }

        for key in libraryFields.keys.sorted() where !usedLibraryKeys.contains(key) {
            warning("taskLibrary '\(key)'", "isn't used on any day.")
        }

        guard errors.isEmpty, let name, let start else { return result(nil) }
        if weekly.values.allSatisfy({ $0.tasks.isEmpty }) && overrides.values.allSatisfy({ $0.tasks.isEmpty }) {
            warning(nil, "This plan has no tasks on any day.")
        }
        return result(Plan(
            name: name,
            startDate: start,
            endDate: end,
            defaultReadSeconds: defaultReadSeconds,
            library: resolvedLibrary,
            weeklyTemplate: weekly,
            dateOverrides: overrides
        ))
    }

    private func result(_ plan: Plan?) -> PlanParseResult {
        PlanParseResult(plan: errors.isEmpty ? plan : nil, errors: errors, warnings: warnings)
    }

    // MARK: - Sections of the file

    private mutating func checkSchemaVersion(_ obj: [String: JSONValue]) -> Bool {
        switch nonNull(obj["schemaVersion"]) {
        case nil:
            error(nil, "Missing schemaVersion. Add \"schemaVersion\": 1 at the top of the plan.")
            return false
        case .number(let version)? where version == Double(Plan.supportedSchemaVersion):
            return true
        case .number(let version)?:
            error(nil, "schemaVersion \(JSONValue.number(version).brief) isn't supported. This version of PlanAlarm only understands schemaVersion 1. Update the app, or regenerate the plan for version 1.")
            return false
        case let other?:
            typeError(nil, "schemaVersion", expected: "the number 1", found: other)
            return false
        }
    }

    private mutating func parseMode(_ obj: [String: JSONValue], at loc: String) -> DateOverride.Mode? {
        switch nonNull(obj["mode"]) {
        case nil:
            error(loc, "needs a mode: \"add\" (add tasks to the normal day) or \"replace\" (use only these tasks).")
            return nil
        case .string(let raw)?:
            guard let mode = DateOverride.Mode(rawValue: raw) else {
                error(loc, "mode '\(raw)' isn't valid. Use \"add\" or \"replace\".")
                return nil
            }
            return mode
        case let other?:
            typeError(loc, "mode", expected: "\"add\" or \"replace\"", found: other)
            return nil
        }
    }

    private mutating func parseDay(_ value: JSONValue, at loc: String) -> (note: String?, tasks: [PlanTask])? {
        guard case .object(let obj) = value else {
            typeError(loc, nil, expected: "an object like { \"tasks\": [ … ] }", found: value)
            return nil
        }
        let before = errors.count
        let note = optionalString(obj, "dayNote", at: loc)
        var tasks: [PlanTask] = []
        switch nonNull(obj["tasks"]) {
        case nil:
            break
        case .array(let entries)?:
            for (index, entry) in entries.enumerated() {
                if let task = parseTaskEntry(entry, at: "\(loc), task \(index + 1)") {
                    tasks.append(task)
                }
            }
        case let other?:
            typeError(loc, "tasks", expected: "a list [ … ]", found: other)
        }
        return errors.count == before ? (note, tasks) : nil
    }

    private mutating func parseLibraryEntry(_ key: String, _ value: JSONValue) {
        let loc = "taskLibrary '\(key)'"
        guard case .object(let obj) = value else {
            typeError(loc, nil, expected: "an object { … }", found: value)
            brokenLibraryKeys.insert(key)
            return
        }
        guard let fields = parseTaskFields(obj, at: loc),
              let task = makeTask(fields, ref: key, at: loc) else {
            brokenLibraryKeys.insert(key)
            return
        }
        libraryFields[key] = fields
        resolvedLibrary[key] = task
    }

    private mutating func parseTaskEntry(_ value: JSONValue, at loc: String) -> PlanTask? {
        guard case .object(let obj) = value else {
            typeError(loc, nil, expected: "an object { … }", found: value)
            return nil
        }
        guard var fields = parseTaskFields(obj, at: loc) else { return nil }
        var ref: String?
        switch nonNull(obj["taskRef"]) {
        case nil:
            break
        case .string(let key)?:
            if let base = libraryFields[key] {
                fields = base.overridden(by: fields)
                ref = key
                usedLibraryKeys.insert(key)
            } else if brokenLibraryKeys.contains(key) {
                return nil // the library entry's own error is already reported
            } else {
                error(loc, "taskRef '\(key)' isn't in taskLibrary.\(suggestion(for: key))")
                return nil
            }
        case let other?:
            typeError(loc, "taskRef", expected: "text", found: other)
            return nil
        }
        if ref == nil && fields.title == nil {
            error(loc, "needs a title, or a taskRef that points to an entry in taskLibrary.")
            return nil
        }
        return makeTask(fields, ref: ref, at: loc)
    }

    private mutating func makeTask(_ fields: TaskFields, ref: String?, at loc: String) -> PlanTask? {
        if fields.title == nil { error(loc, "needs a title.") }
        if fields.category == nil {
            error(loc, "needs a category, such as \"gym\", \"mobility\", \"study\", \"nutrition\" or \"other\".")
        }
        guard let title = fields.title, let category = fields.category else { return nil }
        return PlanTask(
            taskRef: ref,
            title: title,
            category: category,
            summary: fields.summary,
            sections: fields.sections ?? [],
            durationMinutes: fields.durationMinutes,
            readSeconds: fields.readSeconds ?? defaultReadSeconds,
            suggestedTime: fields.suggestedTime
        )
    }

    /// Reads the task fields that are present. Returns nil if any of them is invalid.
    private mutating func parseTaskFields(_ obj: [String: JSONValue], at loc: String) -> TaskFields? {
        let before = errors.count
        var fields = TaskFields()
        fields.title = optionalString(obj, "title", at: loc, allowEmpty: false)
        fields.category = optionalString(obj, "category", at: loc, allowEmpty: false)
        fields.durationMinutes = optionalInt(obj, "durationMinutes", in: Self.durationRange, at: loc)
        fields.readSeconds = optionalInt(obj, "readSeconds", in: Self.readSecondsRange, at: loc)

        switch nonNull(obj["suggestedTime"]) {
        case nil:
            break
        case .string(let raw)?:
            if let time = TimeOfDay(string: raw) {
                fields.suggestedTime = time
            } else {
                error(loc, "suggestedTime '\(raw)' is not a valid time. Use 24-hour HH:mm, like \"07:30\" or \"18:00\".")
            }
        case let other?:
            typeError(loc, "suggestedTime", expected: "text like \"07:30\"", found: other)
        }

        switch nonNull(obj["description"]) {
        case nil:
            break
        case .object(let description)?:
            fields.summary = optionalString(description, "summary", at: loc, label: "description.summary")
            fields.sections = parseSections(description, at: loc)
        case let other?:
            typeError(loc, "description", expected: "an object like { \"summary\": \"…\", \"sections\": [ … ] }", found: other)
        }
        return errors.count == before ? fields : nil
    }

    private mutating func parseSections(_ description: [String: JSONValue], at loc: String) -> [TaskSection]? {
        switch nonNull(description["sections"]) {
        case nil:
            return nil
        case .array(let list)?:
            var sections: [TaskSection] = []
            for (index, value) in list.enumerated() {
                let sectionLoc = "\(loc), section \(index + 1)"
                guard case .object(let obj) = value else {
                    typeError(sectionLoc, nil, expected: "an object like { \"title\": \"…\", \"items\": [ … ] }", found: value)
                    continue
                }
                let title = requiredString(obj, "title", at: sectionLoc)
                var items: [String] = []
                switch nonNull(obj["items"]) {
                case nil:
                    break
                case .array(let rawItems)?:
                    for (itemIndex, item) in rawItems.enumerated() {
                        if case .string(let text) = item {
                            items.append(text)
                        } else {
                            typeError("\(sectionLoc), item \(itemIndex + 1)", nil, expected: "text", found: item)
                        }
                    }
                case let other?:
                    typeError(sectionLoc, "items", expected: "a list of text", found: other)
                }
                if let title { sections.append(TaskSection(title: title, items: items)) }
            }
            return sections
        case let other?:
            typeError(loc, "description.sections", expected: "a list [ … ]", found: other)
            return nil
        }
    }

    // MARK: - Field helpers

    private func nonNull(_ value: JSONValue?) -> JSONValue? {
        if case .null? = value { return nil }
        return value
    }

    private mutating func object(_ obj: [String: JSONValue], _ key: String, at loc: String?) -> [String: JSONValue]? {
        switch nonNull(obj[key]) {
        case nil: return nil
        case .object(let value)?: return value
        case let other?:
            typeError(loc, key, expected: "an object { … }", found: other)
            return nil
        }
    }

    private mutating func requiredString(_ obj: [String: JSONValue], _ key: String, at loc: String?) -> String? {
        guard nonNull(obj[key]) != nil else {
            error(loc, "\(loc == nil ? "Missing" : "missing") \(key).")
            return nil
        }
        return optionalString(obj, key, at: loc, allowEmpty: false)
    }

    private mutating func optionalString(_ obj: [String: JSONValue], _ key: String, at loc: String?,
                                         label: String? = nil, allowEmpty: Bool = true) -> String? {
        let label = label ?? key
        switch nonNull(obj[key]) {
        case nil:
            return nil
        case .string(let value)?:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !allowEmpty && trimmed.isEmpty {
                error(loc, "\(label) can't be empty.")
                return nil
            }
            return trimmed
        case let other?:
            typeError(loc, label, expected: "text", found: other)
            return nil
        }
    }

    private mutating func optionalInt(_ obj: [String: JSONValue], _ key: String, in range: ClosedRange<Int>,
                                      at loc: String?) -> Int? {
        switch nonNull(obj[key]) {
        case nil:
            return nil
        case .number(let value)? where value.rounded() == value && abs(value) < 1e9:
            let number = Int(value)
            guard range.contains(number) else {
                error(loc, "\(key) must be between \(range.lowerBound) and \(range.upperBound), but is \(number).")
                return nil
            }
            return number
        case let other?:
            typeError(loc, key, expected: "a whole number", found: other)
            return nil
        }
    }

    private mutating func requiredDate(_ obj: [String: JSONValue], _ key: String, at loc: String?) -> LocalDate? {
        guard nonNull(obj[key]) != nil else {
            error(loc, "Missing \(key). Use YYYY-MM-DD, like \"2026-10-01\".")
            return nil
        }
        return optionalDate(obj, key, at: loc)
    }

    private mutating func optionalDate(_ obj: [String: JSONValue], _ key: String, at loc: String?) -> LocalDate? {
        guard let raw = optionalString(obj, key, at: loc) else { return nil }
        guard let date = LocalDate(isoString: raw) else {
            error(loc, "\(key) '\(raw)' isn't a valid date. Use YYYY-MM-DD, like \"2026-10-01\".")
            return nil
        }
        return date
    }

    // MARK: - Reporting

    private mutating func error(_ location: String?, _ message: String) {
        errors.append(PlanIssue(location: location, message: message))
    }

    private mutating func warning(_ location: String?, _ message: String) {
        warnings.append(PlanIssue(location: location, message: message))
    }

    private mutating func typeError(_ location: String?, _ field: String?, expected: String, found: JSONValue) {
        let subject = field.map { "\($0) should be" } ?? (location == nil ? "Should be" : "should be")
        error(location, "\(subject) \(expected), but found \(found.brief).")
    }

    private func suggestion(for key: String) -> String {
        let known = Array(libraryFields.keys) + Array(brokenLibraryKeys)
        let best = known
            .map { ($0, Self.editDistance($0, key)) }
            .min { $0.1 < $1.1 || ($0.1 == $1.1 && $0.0 < $1.0) }
        if let best, best.1 <= max(2, key.count / 3) {
            return " Did you mean '\(best.0)'?"
        }
        if !known.isEmpty && known.count <= 10 {
            return " Available keys: \(known.sorted().joined(separator: ", "))."
        }
        return ""
    }

    static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs), b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1,
                                 previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}

/// The task fields present on one JSON object (library entry or day entry), before merging.
private struct TaskFields {
    var title: String?
    var category: String?
    var summary: String?
    var sections: [TaskSection]?
    var durationMinutes: Int?
    var readSeconds: Int?
    var suggestedTime: TimeOfDay?

    /// Fields set on `entry` win; description.summary and description.sections override separately.
    func overridden(by entry: TaskFields) -> TaskFields {
        TaskFields(
            title: entry.title ?? title,
            category: entry.category ?? category,
            summary: entry.summary ?? summary,
            sections: entry.sections ?? sections,
            durationMinutes: entry.durationMinutes ?? durationMinutes,
            readSeconds: entry.readSeconds ?? readSeconds,
            suggestedTime: entry.suggestedTime ?? suggestedTime
        )
    }
}
