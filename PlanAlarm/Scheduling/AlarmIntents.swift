import AppIntents
import Foundation

/// Runs when the task alarm's Stop button is pressed: the alarm comes back after the snooze length.
struct SnoozeTaskIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Snooze Task Alarm"
    static let isDiscoverable = false

    @Parameter(title: "Task")
    var taskKey: String

    init() {}

    init(taskKey: String) {
        self.taskKey = taskKey
    }

    func perform() async throws -> some IntentResult {
        await AlarmService.handleStop(taskKey: taskKey)
        return .result()
    }
}

/// The task alarm's "Open task" button: opens the app on that task.
struct OpenTaskIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Open Task"
    static let isDiscoverable = false
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Task")
    var taskKey: String

    @Parameter(title: "Alarm")
    var alarmID: String

    init() {}

    init(taskKey: String, alarmID: String) {
        self.taskKey = taskKey
        self.alarmID = alarmID
    }

    func perform() async throws -> some IntentResult {
        await AlarmService.handleOpen(taskKey: taskKey)
        return .result()
    }
}

/// The wake-up alarm's "Open" button: silences the alarm and opens the app.
struct OpenAppFromAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Open PlanAlarm"
    static let isDiscoverable = false
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Alarm")
    var alarmID: String

    init() {}

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    func perform() async throws -> some IntentResult {
        await AlarmService.handleOpenApp(alarmID: alarmID)
        return .result()
    }
}
