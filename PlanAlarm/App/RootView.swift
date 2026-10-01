import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum AppTab: String, CaseIterable, Hashable {
    case today, plan, history, settings
}

struct RootView: View {
    @State private var selection: AppTab = .today
    @State private var importer = ImportController()
    @State private var alarms = AlarmService.shared
    @State private var router = AppRouter.shared
    /// The calendar day shown on the Today tab; updated whenever the app becomes active.
    @State private var today = LocalDate.today()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var isShowingOnboarding = false
    @State private var onboardingNextStep: OnboardingNextStep = .none
    @Environment(\.scenePhase) private var scenePhase

    /// The task shown full screen until it's acknowledged.
    private var presentedTask: Binding<PendingTaskAlarm?> {
        Binding(
            get: { router.presentedTaskKey.flatMap { alarms.registry.task(forKey: $0) } },
            set: { if $0 == nil { router.presentedTaskKey = nil } }
        )
    }

    private var isShowingWakeUp: Binding<Bool> {
        Binding(
            get: { router.wakeUpDay != nil },
            set: { if !$0 { router.wakeUpDay = nil } }
        )
    }

    /// The walk was opened from Today before the wake-up time.
    private var isEarlyWakeUp: Bool {
        guard let day = router.wakeUpDay, let first = AppSettings.current().wakeSchedule.ringDates(on: day).first else { return false }
        return first > .now
    }

    var body: some View {
        @Bindable var importer = importer

        TabView(selection: $selection) {
            Tab("Today", systemImage: "sun.max", value: AppTab.today) {
                TodayView(date: today)
                    .id(today)
            }
            Tab("Plan", systemImage: "list.bullet.rectangle", value: AppTab.plan) {
                PlanView()
            }
            Tab("History", systemImage: "calendar", value: AppTab.history) {
                HistoryView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        // "Open in PlanAlarm" from Files, AirDrop, WhatsApp, Mail…
        .onOpenURL { url in
            importer.importFile(at: url)
        }
        .fileImporter(
            isPresented: $importer.isShowingFileImporter,
            allowedContentTypes: [.dayplan, .json, .plainText]
        ) { result in
            switch result {
            case .success(let url): importer.importFile(at: url)
            case .failure(let error): importer.readError = error.localizedDescription
            }
        }
        .sheet(item: $importer.sheet) { sheet in
            switch sheet {
            case .paste: PastePlanView()
            case .newPlan: NewPlanView()
            case .preview(let pending): PlanImportPreviewView(pending: pending)
            }
        }
        .alert("Couldn't open the plan", isPresented: .init(
            get: { importer.readError != nil },
            set: { if !$0 { importer.readError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(importer.readError ?? "")
        }
        .onChange(of: importer.importCount) {
            selection = .plan
        }
        // A task alarm that hasn't been acknowledged takes over the screen, whatever route opened the app.
        .fullScreenCover(item: presentedTask) { pending in
            TaskAlarmView(
                pending: pending,
                unlockSeconds: alarms.unlockSeconds(for: pending),
                snoozeCount: alarms.snoozeCount(for: pending)
            ) {
                TaskActions.start(pending)
                showNextPendingTask()
            } onReschedule: { time in
                router.presentedTaskKey = nil
                Task {
                    await TaskActions.reschedule(pending, to: time)
                    router.showPendingTaskIfNeeded()
                }
            } onSkip: {
                TaskActions.skip(pending)
                showNextPendingTask()
            }
        }
        // The wake-up walk takes over the screen until it's done; the wake-up rings stop with it.
        .fullScreenCover(isPresented: isShowingWakeUp) {
            WakeUpView(goal: AppSettings.current().wakeSteps, isEarly: isEarlyWakeUp) {
                if let day = router.wakeUpDay {
                    alarms.confirmAwake(on: day)
                }
                router.wakeUpDay = nil
                selection = .today
                router.showPendingTaskIfNeeded()
            } onCancel: {
                router.wakeUpDay = nil
            }
        }
        .onChange(of: scenePhase, initial: true) {
            switch scenePhase {
            case .active:
                today = .today()
                // Days that passed without a check-in are recorded (and frozen) before anything else.
                DayStore.recordDaysWithoutCheckIn(before: today)
                // Until the day is locked in, opening the app goes to the morning check-in.
                if !DayStore.isLockedIn(today) && importer.sheet == nil {
                    selection = .today
                }
                Task {
                    await TaskActions.reconcile()
                    await alarms.refresh()
                    syncTaskStatuses()
                    router.showWakeUpIfNeeded()
                    router.showPendingTaskIfNeeded()
                }
            case .background:
                // Top up the wake-up rings (the next wake-up may have moved on since the last refresh).
                alarms.updateWakeAlarms()
            default:
                break
            }
        }
        .task {
            // Catch alarms that go off while the app is open, and the date changing at midnight.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                if LocalDate.today() != today {
                    today = .today()
                    DayStore.recordDaysWithoutCheckIn(before: today)
                }
                syncTaskStatuses()
                router.showWakeUpIfNeeded()
                router.showPendingTaskIfNeeded()
            }
        }
        // First-launch welcome (skipped for people who already have plans or history).
        .fullScreenCover(isPresented: $isShowingOnboarding, onDismiss: runOnboardingNextStep) {
            OnboardingView { step in
                onboardingNextStep = step
                hasCompletedOnboarding = true
                isShowingOnboarding = false
            }
        }
        .onAppear {
            guard !hasCompletedOnboarding else { return }
            if hasExistingData {
                hasCompletedOnboarding = true
            } else {
                isShowingOnboarding = true
            }
        }
        .onChange(of: hasCompletedOnboarding) {
            // Settings → Show Welcome Screens Again.
            if !hasCompletedOnboarding { isShowingOnboarding = true }
        }
        .environment(importer)
    }

    private var hasExistingData: Bool {
        let context = AppDatabase.context
        let plans = (try? context.fetchCount(FetchDescriptor<StoredPlan>())) ?? 0
        let days = (try? context.fetchCount(FetchDescriptor<DayRecord>())) ?? 0
        return plans + days > 0
    }

    /// Opens the plan screen chosen on the last welcome page, once the welcome screens have closed.
    private func runOnboardingNextStep() {
        let step = onboardingNextStep
        onboardingNextStep = .none
        switch step {
        case .importFile: importer.showFileImporter()
        case .paste: importer.showPaste()
        case .sample: importer.loadSample()
        case .newPlan: importer.showNewPlan()
        case .none: break
        }
    }

    private func showNextPendingTask() {
        router.presentedTaskKey = nil
        router.showPendingTaskIfNeeded()
    }

    /// Marks tasks whose alarm has started ringing.
    private func syncTaskStatuses() {
        DayStore.markRinging(alarms.tasksPendingAcknowledgement.map { (key: $0.key, firstAlarmAt: $0.firstAlarmAt) })
    }
}

#Preview {
    RootView()
        .modelContainer(for: [StoredPlan.self, AppSettings.self, ExtraTask.self, DayRecord.self, TaskRecord.self], inMemory: true)
}
