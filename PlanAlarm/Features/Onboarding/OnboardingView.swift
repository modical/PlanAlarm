import SwiftData
import SwiftUI
import UIKit

/// What to open after the welcome screens (the plan sheets can't be shown on top of them).
enum OnboardingNextStep {
    case importFile, paste, sample, newPlan, none
}

/// First-launch welcome: what the app does, the two permissions, the wake-up time, and a plan.
struct OnboardingView: View {
    let onFinish: (OnboardingNextStep) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRecords: [AppSettings]
    @State private var alarms = AlarmService.shared
    @State private var notificationPermission: FollowUpService.Permission?
    @State private var page = 0

    private let lastPage = 4

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcomePage.tag(0)
                alarmsPage.tag(1)
                notificationsPage.tag(2)
                wakePage.tag(3)
                planPage.tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            if page < lastPage {
                Button {
                    withAnimation { page += 1 }
                } label: {
                    Text("Continue").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
            }
        }
        .interactiveDismissDisabled()
        .task {
            _ = AppSettings.current(in: modelContext)
            notificationPermission = await FollowUpService.permission()
        }
    }

    // MARK: Pages

    private var welcomePage: some View {
        OnboardingPage(icon: "alarm.waves.left.and.right", title: "Welcome to PlanAlarm",
                       text: "Your daily plan, with reminders that behave like real alarms.") {
            VStack(alignment: .leading, spacing: 14) {
                Bullet(icon: "speaker.wave.3", text: "Alarms ring through silent mode and Focus.")
                Bullet(icon: "arrow.clockwise", text: "They come back every few minutes until you open the task and read it.")
                Bullet(icon: "sun.max", text: "Each morning you check in: choose today's times, then lock in your day.")
                Bullet(icon: "calendar", text: "History and streaks show how your days went.")
            }
        }
    }

    private var alarmsPage: some View {
        OnboardingPage(icon: "alarm", title: "Allow alarms",
                       text: "PlanAlarm needs permission to ring like an alarm. Without it, nothing can ring.") {
            switch alarms.permission {
            case .allowed:
                Label("Alarms allowed", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
            case .denied:
                VStack(spacing: 10) {
                    Label("Alarms are turned off", systemImage: "xmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            case .notAsked:
                Button("Allow Alarms") {
                    Task { await alarms.requestAuthorization() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    private var notificationsPage: some View {
        OnboardingPage(icon: "bell.badge", title: "Allow notifications",
                       text: "After you start a task, a normal notification asks whether you finished it, so you can answer Done or Skipped without opening the app.") {
            switch notificationPermission {
            case .allowed:
                Label("Notifications allowed", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
            case .denied:
                Label("Notifications are off (you can turn them on in Settings later)", systemImage: "bell.slash")
                    .foregroundStyle(.secondary)
            default:
                Button("Allow Notifications") {
                    Task {
                        await FollowUpService.ensurePermission()
                        notificationPermission = await FollowUpService.permission()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    private var wakePage: some View {
        OnboardingPage(icon: "sun.horizon", title: "Wake-up time",
                       text: "A wake-up alarm starts your day with the morning check-in. You can set different times for single days in Settings.") {
            if let settings = settingsRecords.first {
                WakeTimeEditor(settings: settings)
            }
        }
    }

    private var planPage: some View {
        OnboardingPage(icon: "list.bullet.rectangle", title: "Load your plan",
                       text: "A plan is a .dayplan file with your weekly routine. Import one, or try the sample plan first.") {
            VStack(spacing: 10) {
                finishButton("Load Sample Plan", icon: "sparkles", step: .sample, prominent: true)
                finishButton("Import from Files…", icon: "folder", step: .importFile)
                finishButton("Paste Plan JSON…", icon: "doc.on.clipboard", step: .paste)
                finishButton("New Empty Plan…", icon: "square.and.pencil", step: .newPlan)
                Button("Not now") { finish(.none) }
                    .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func finishButton(_ title: String, icon: String, step: OnboardingNextStep, prominent: Bool = false) -> some View {
        if prominent {
            Button { finish(step) } label: {
                Label(title, systemImage: icon).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        } else {
            Button { finish(step) } label: {
                Label(title, systemImage: icon).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private func finish(_ step: OnboardingNextStep) {
        if let settings = settingsRecords.first {
            alarms.applyWakeSchedule(settings.wakeSchedule)
        }
        onFinish(step)
    }
}

private struct OnboardingPage<Content: View>: View {
    let icon: String
    let title: String
    let text: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: icon)
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                    .padding(.top, 48)
                Text(title)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(text)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                content()
                    .padding(.top, 8)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 60)
        }
    }
}

private struct Bullet: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 24)
            Text(text)
        }
    }
}

private struct WakeTimeEditor: View {
    @Bindable var settings: AppSettings

    var body: some View {
        VStack(spacing: 12) {
            Toggle("Wake-up alarm", isOn: $settings.wakeEnabled)
            if settings.wakeEnabled {
                DatePicker("Time", selection: timeBinding(
                    get: { settings.wakeSchedule.defaultTime },
                    set: { settings.wakeSchedule.defaultTime = $0 }
                ), displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .environment(\.calendar, .plan)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}
