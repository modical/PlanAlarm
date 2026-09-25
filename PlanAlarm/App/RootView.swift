import SwiftUI
import UniformTypeIdentifiers

enum AppTab: String, CaseIterable, Hashable {
    case today, plan, history, settings
}

struct RootView: View {
    @State private var selection: AppTab = .today
    @State private var importer = ImportController()

    var body: some View {
        @Bindable var importer = importer

        TabView(selection: $selection) {
            Tab("Today", systemImage: "sun.max", value: AppTab.today) {
                TodayView()
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
        .environment(importer)
    }
}

#Preview {
    RootView()
        .modelContainer(for: StoredPlan.self, inMemory: true)
}
