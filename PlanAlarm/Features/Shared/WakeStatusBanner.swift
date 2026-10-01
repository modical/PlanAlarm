import SwiftData
import SwiftUI

/// Says what the next wake-up will do, so it's never a surprise: when it rings, that it keeps ringing
/// until the walk, or that it's off or not actually set in iOS. Before today's wake-up time it offers
/// the walk early, which cancels today's rings.
struct WakeStatusBanner: View {
    @Query private var settingsRecords: [AppSettings]
    @State private var alarms = AlarmService.shared
    @State private var router = AppRouter.shared

    var body: some View {
        if let settings = settingsRecords.first, alarms.permission == .allowed {
            content(settings)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(tint(settings).opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private enum Status {
        case off
        case noneThisWeek
        case next(Date, problem: Bool)
    }

    private func status(_ settings: AppSettings) -> Status {
        guard settings.wakeEnabled else { return .off }
        guard let next = alarms.nextWakeUp() else { return .noneThisWeek }
        // Right after a change the rings are still being set; only warn once that's finished.
        return .next(next.date, problem: next.isSet == false && !alarms.isUpdatingWakeAlarms)
    }

    private func tint(_ settings: AppSettings) -> Color {
        switch status(settings) {
        case .off, .noneThisWeek: .gray
        case .next(_, let problem): problem ? .red : .green
        }
    }

    @ViewBuilder
    private func content(_ settings: AppSettings) -> some View {
        let today = LocalDate.today()
        VStack(alignment: .leading, spacing: 8) {
            if alarms.awakeDays.contains(today.description) {
                Label("You're up today.", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            }
            switch status(settings) {
            case .off:
                Label("Wake-up alarm is off", systemImage: "alarm")
                    .font(.headline)
                Text("Turn it on in Settings → Alarms.")
                    .font(.subheadline)
            case .noneThisWeek:
                Label("No wake-up alarm in the next 7 days", systemImage: "alarm")
                    .font(.headline)
                Text("Every day is switched off in Settings → Alarms → Wake-up alarm.")
                    .font(.subheadline)
            case .next(let date, let problem):
                Label("Next wake-up: \(date.formatted(.dateTime.weekday(.wide).hour().minute()))", systemImage: "alarm.fill")
                    .font(.headline)
                if problem {
                    Text("It isn't set in iOS. Open Settings → Alarms and check for a message there. \(alarms.lastError ?? "")")
                        .font(.subheadline)
                } else {
                    Text("Rings again and again (every 9, 7, 5, then 3 min, up to 2 h) until you walk \(settings.wakeSteps) steps in PlanAlarm.")
                        .font(.subheadline)
                }
                if LocalDate(date) == today && !problem {
                    Button("Up already? Walk now to stop today's alarm") {
                        router.wakeUpDay = today
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
    }
}
