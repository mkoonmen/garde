import SwiftUI
import CloudKit
import UserNotifications

struct GardeSettingsView: View {
    @State private var engine = ChefEngine.shared
    @State private var brain = ChefEngine.shared.brain
    @State private var sync = GardeStore.syncEnabled
    @State private var iCloudStatus = "Checking…"
    @AppStorage("weeklyNudge") private var weeklyNudge = true
    @AppStorage("leftoverNudge") private var leftoverNudge = true
    @AppStorage("cookTips") private var cookTips = true

    var body: some View {
        Form { Group {
            Section {
                Toggle("Sunday \"plan the week\" reminder", isOn: $weeklyNudge)
                    .onChange(of: weeklyNudge) { _, on in
                        if !on { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["weekly-plan"]) }
                    }
                Toggle("Leftovers-for-lunch reminder", isOn: $leftoverNudge)
                Toggle("Technique tips in cook mode", isOn: $cookTips)
            } footer: { Text("Sunday: 5 PM, with how much in your kitchen expires that week. Leftovers: 11:30 the day after you save them.") }
            Section {
                Picker("Chef brain", selection: $brain) {
                    ForEach(ChefBrain.allCases) { Text($0.label).tag($0) }
                }
                .onChange(of: brain) { _, b in engine.brain = b }
                Text(brain.detail).font(.footnote).foregroundStyle(.secondary)
                if brain == .local8B {
                    if !engine.localSupported {
                        Label("Needs iOS 27 or later. Using Apple's model for now.", systemImage: "info.circle").font(.footnote)
                    } else {
                        switch engine.downloadState {
                        case .notDownloaded:
                            Button("Download Qwen3 8B (4.7 GB)", systemImage: "arrow.down.circle") { Task { await engine.downloadLocalModel() } }
                            Text("Use Wi-Fi and keep Garde open until it finishes.").font(.caption).foregroundStyle(.secondary)
                        case .downloading(let p):
                            ProgressView(value: p) { Text("Downloading… \(Int(p * 100))%") }
                        case .ready:
                            Label("Downloaded. Runs fully offline.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        case .failed(let why):
                            Label(why, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                            Button("Try again") { Task { await engine.downloadLocalModel() } }
                        }
                    }
                }
            } header: { Text("Chef") } footer: {
                Text("Both brains run on this iPhone. Scanning always uses Apple's model because it's faster.")
            }

            Section {
                Toggle("Sync with iCloud", isOn: $sync)
                    .onChange(of: sync) { _, v in UserDefaults(suiteName: GardeStore.appGroup)?.set(v, forKey: "icloudSync") }
                LabeledContent("iCloud", value: iCloudStatus)
            } header: { Text("iCloud") } footer: {
                Text("Keeps your kitchen, list, recipes and profile the same on every device signed in to your Apple ID, in your private iCloud. Takes effect next time Garde opens.")
            }

            Section("Deals") { NavigationLink("Weekly ads & stores") { DealsView() } }
        }.listRowBackground(RowGlass()) }
        .gardePage()
        .navigationTitle("Settings")
        .task {
            #if targetEnvironment(simulator)
            let status: CKAccountStatus? = nil   // unsigned simulator builds have no iCloud entitlement (CKContainer would trap)
            #else
            let status = try? await CKContainer(identifier: GardeStore.cloudContainer).accountStatus()
            #endif
            iCloudStatus = switch status {
            case .available: "Signed in"
            case .noAccount: "Not signed in"
            case .restricted: "Restricted"
            default: "Unavailable"
            }
        }
    }
}
