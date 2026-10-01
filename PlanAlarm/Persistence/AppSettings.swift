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
    /// How long a task must be on screen before its Stop Alarm button unlocks
    /// (a task's own readSeconds in the plan file wins).
    var stopUnlockSeconds: Int = 30
    /// `AlarmTone` raw values.
    var taskToneID: String = AlarmTone.system.rawValue
    var wakeToneID: String = AlarmTone.system.rawValue
    /// Steps to walk in the app to stop the wake-up rings.
    var wakeSteps: Int = 30
    /// No longer used (the v1.0 check-in reminder, replaced by the repeating wake-up alarm).
    /// Kept so existing databases open unchanged.
    var checkInReminderEnabled: Bool = true
    var checkInReminderMinutes: Int = 30
    /// "Did you finish …?" notification after a task starts.
    var followUpEnabled: Bool = true

    init() {}

    var taskTone: AlarmTone {
        get { AlarmTone(rawValue: taskToneID) ?? .system }
        set { taskToneID = newValue.rawValue }
    }

    var wakeTone: AlarmTone {
        get { AlarmTone(rawValue: wakeToneID) ?? .system }
        set { wakeToneID = newValue.rawValue }
    }

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
