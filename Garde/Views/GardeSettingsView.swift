import SwiftUI
import CloudKit

struct GardeSettingsView: View {
    @State private var engine = ChefEngine.shared
    @State private var brain = ChefEngine.shared.brain
    @State private var sync = GardeStore.syncEnabled
    @State private var feed = KitchenFeed.enabled
    @State private var iCloudStatus = "Checking…"

    var body: some View {
        Form {
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

            Section {
                Toggle("Share kitchen with Koonmen OS", isOn: $feed).onChange(of: feed) { _, v in KitchenFeed.enabled = v }
                LabeledContent("Feed", value: KitchenFeed.isAvailable ? "Ready" : "Needs iCloud Drive")
            } header: { Text("TVs") } footer: {
                Text("Publishes tonight's dinner, what to use first, and the live cook-mode step to your iCloud Drive, where the Koonmen OS bridge on the Mac picks it up for the TVs. Read-only.")
            }

            Section("Deals") { NavigationLink("Weekly ads & stores") { DealsView() } }
        }
        .gardePage()
        .navigationTitle("Settings")
        .task {
            let status = try? await CKContainer(identifier: GardeStore.cloudContainer).accountStatus()
            iCloudStatus = switch status {
            case .available: "Signed in"
            case .noAccount: "Not signed in"
            case .restricted: "Restricted"
            default: "Unavailable"
            }
        }
    }
}
