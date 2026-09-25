import SwiftData
import SwiftUI

/// Wake-up alarm: on/off, a default time, and per-weekday switches and times.
struct WakeSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Wake-up alarm", isOn: $settings.wakeEnabled)
                if settings.wakeEnabled {
                    DatePicker("Time", selection: timeBinding(
                        get: { settings.wakeSchedule.defaultTime },
                        set: { settings.wakeSchedule.defaultTime = $0 }
                    ), displayedComponents: .hourAndMinute)
                }
            } footer: {
                Text("Rings every day at this time, through silent mode and Focus. Change single days below.")
            }

            if settings.wakeEnabled {
                Section("Days") {
                    ForEach(Weekday.ordered(), id: \.self) { weekday in
                        WakeDayRow(settings: settings, weekday: weekday)
                    }
                }
            }
        }
        .environment(\.calendar, .plan)
        .navigationTitle("Wake-up Alarm")
    }
}

private struct WakeDayRow: View {
    @Bindable var settings: AppSettings
    let weekday: Weekday

    private var rule: WakeDayRule { settings.wakeSchedule.rule(for: weekday) }

    private func update(_ change: (inout WakeDayRule) -> Void) {
        var schedule = settings.wakeSchedule
        var rule = schedule.rule(for: weekday)
        change(&rule)
        schedule.rules[weekday] = rule
        settings.wakeSchedule = schedule
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(weekday.displayName, isOn: .init(
                get: { rule.isEnabled },
                set: { newValue in update { $0.isEnabled = newValue } }
            ))
            if rule.isEnabled {
                if rule.customTime != nil {
                    HStack {
                        DatePicker("Own time", selection: timeBinding(
                            get: { rule.customTime ?? settings.wakeSchedule.defaultTime },
                            set: { newTime in update { $0.customTime = newTime } }
                        ), displayedComponents: .hourAndMinute)
                        Button("Reset", systemImage: "arrow.uturn.backward") {
                            update { $0.customTime = nil }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    }
                } else {
                    Button("Use a different time on \(weekday.displayName)s") {
                        update { $0.customTime = settings.wakeSchedule.defaultTime }
                    }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
                }
            }
        }
    }
}

/// Binds a DatePicker (hour and minute) to a `TimeOfDay`.
@MainActor
func timeBinding(get: @escaping () -> TimeOfDay, set: @escaping (TimeOfDay) -> Void) -> Binding<Date> {
    Binding(
        get: {
            let time = get()
            return LocalDate.today().date(hour: time.hour, minute: time.minute)
        },
        set: { date in
            let parts = Calendar.plan.dateComponents([.hour, .minute], from: date)
            if let time = TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0) {
                set(time)
            }
        }
    )
}
