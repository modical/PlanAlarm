import Foundation
import SwiftData

/// User settings (one record). More settings arrive in later phases.
@Model
final class AppSettings {
    var wakeEnabled: Bool = true
    var wakeHour: Int = 7
    var wakeMinute: Int = 0
    /// JSON-encoded `[WakeDayRule]` per weekday (see `wakeSchedule`).
    var wakeDayRulesJSON: Data = Data()
    var snoozeMinutes: Int = 5

    init() {}

    /// The wake-up alarm settings as a value type.
    var wakeSchedule: WakeSchedule {
        get {
            let rules = (try? JSONDecoder().decode([Weekday: WakeDayRule].self, from: wakeDayRulesJSON)) ?? [:]
            return WakeSchedule(
                isEnabled: wakeEnabled,
                defaultTime: TimeOfDay(hour: wakeHour, minute: wakeMinute) ?? WakeSchedule.standard.defaultTime,
                rules: rules
            )
        }
        set {
            wakeEnabled = newValue.isEnabled
            wakeHour = newValue.defaultTime.hour
            wakeMinute = newValue.defaultTime.minute
            wakeDayRulesJSON = (try? JSONEncoder().encode(newValue.rules)) ?? Data()
        }
    }

    /// The settings record, created with defaults on first use.
    @MainActor
    static func current(in context: ModelContext = AppDatabase.context) -> AppSettings {
        if let existing = try? context.fetch(FetchDescriptor<AppSettings>()).first {
            return existing
        }
        let settings = AppSettings()
        context.insert(settings)
        try? context.save()
        return settings
    }
}
