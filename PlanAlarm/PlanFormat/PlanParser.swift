import Foundation

/// A human-readable problem found in a plan file, e.g.
/// "Monday, task 2: suggestedTime '25:00' is not a valid time. …"
struct PlanIssue: Hashable, Sendable, CustomStringConvertible {
    /// Where the problem is ("Monday, task 2", "taskLibrary 'push-day'"), or nil for the whole file.
    var location: String?
    var message: String

    var description: String {
        location.map { "\($0): \(message)" } ?? message
    }
}

struct PlanParseResult: Sendable {
    /// Present only when there are no errors.
    var plan: Plan?
    var errors: [PlanIssue] = []
    /// Problems that don't stop the plan from being used.
    var warnings: [PlanIssue] = []
    /// The JSON that was actually parsed (after small clean-ups), to store on import.
    var json: Data?

    var isValid: Bool { plan != nil && errors.isEmpty }
}

enum PlanParser {
    static func parse(text: String) -> PlanParseResult {
        parse(Data(text.utf8))
    }

    static func parse(_ input: Data) -> PlanParseResult {
        var data = input
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { // UTF-8 byte-order mark
            data = Data(data.dropFirst(3))
        }
        let text = String(decoding: data, as: UTF8.self)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return PlanParseResult(errors: [PlanIssue(message: "The plan is empty.")])
        }

        var notes: [PlanIssue] = []
        let root: JSONValue
        do {
            root = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            // Text pasted from notes or chat apps sometimes has curly quotes instead of straight ones.
            let straightened = text.replacing("\u{201C}", with: "\"").replacing("\u{201D}", with: "\"")
            if straightened != text,
               let repaired = try? JSONDecoder().decode(JSONValue.self, from: Data(straightened.utf8)) {
                root = repaired
                data = Data(straightened.utf8)
                notes.append(PlanIssue(message: "Curly quotes (“ ”) were changed to straight quotes (\") so the plan could be read."))
            } else {
                return PlanParseResult(errors: [PlanIssue(message: "This isn't valid JSON. \(describe(error))")])
            }
        }

        var validator = PlanValidator()
        var result = validator.validate(root)
        result.warnings.insert(contentsOf: notes, at: 0)
        result.json = data
        return result
    }

    private static func describe(_ error: any Error) -> String {
        guard case DecodingError.dataCorrupted(let context) = error else { return "" }
        if let underlying = context.underlyingError,
           let detail = (underlying as NSError).userInfo[NSDebugDescriptionErrorKey] as? String {
            return detail
        }
        return context.debugDescription
    }
}
