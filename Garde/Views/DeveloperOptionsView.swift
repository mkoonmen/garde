import SwiftUI
import CryptoKit

/// Owner-only settings, hidden from friends who test Garde.
/// Unlocks with a password; only its SHA-256 hash is stored in the app.
enum DeveloperMode {
    static let passwordHash = "b94c8d9689ebaa4e91575db000e8741bf6c553f6ff4e93b8dc0c86be08ac6dea"
    static var unlocked: Bool {
        get { UserDefaults.standard.bool(forKey: "dev.unlocked") }
        set { UserDefaults.standard.set(newValue, forKey: "dev.unlocked") }
    }
    static func check(_ password: String) -> Bool {
        SHA256.hash(data: Data(password.utf8)).map { String(format: "%02x", $0) }.joined() == passwordHash
    }
}

struct DeveloperOptionsView: View {
    @State private var unlocked = DeveloperMode.unlocked
    @State private var password = ""
    @State private var wrong = false

    var body: some View {
        Group {
            if unlocked { DeveloperSettings { unlocked = false } } else { lockScreen }
        }
        .gardePage()
        .navigationTitle("Developer options")
    }

    private var lockScreen: some View {
        Form { Group {
            Section {
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .onSubmit(tryUnlock)
                Button("Unlock", action: tryUnlock).disabled(password.isEmpty)
                if wrong { Text("Wrong password.").foregroundStyle(.red).font(.footnote) }
            } footer: { Text("For the app's owner. Testers don't need anything here.") }
        }.listRowBackground(RowGlass()) }
    }

    private func tryUnlock() {
        if DeveloperMode.check(password) {
            DeveloperMode.unlocked = true
            withAnimation { unlocked = true }
        } else { wrong = true }
        password = ""
    }
}

private struct DeveloperSettings: View {
    var onLock: () -> Void
    @State private var feed = UserDefaults.standard.object(forKey: "feed.enabled") as? Bool ?? true
    @AppStorage("gmail.query") private var query = ""
    @AppStorage("gmail.clientID") private var clientOverride = ""

    var body: some View {
        Form { Group {
            Section {
                Toggle("Share kitchen with Koonmen OS", isOn: $feed)
                    .onChange(of: feed) { _, v in UserDefaults.standard.set(v, forKey: "feed.enabled") }
                LabeledContent("Feed", value: KitchenFeed.isAvailable ? "Ready" : "Needs iCloud Drive")
            } header: { Text("Koonmen OS") } footer: {
                Text("Publishes tonight's dinner, what to use first, and the live cook-mode step to Garde's iCloud Drive folder for the TVs. Read-only.")
            }
            Section {
                TextField("Gmail search", text: $query, prompt: Text("Default: grocery stores and order receipts"), axis: .vertical)
                    .font(.footnote.monospaced())
                TextField("Google client ID override", text: $clientOverride, prompt: Text("Built-in (garde-513820)"))
                    .font(.footnote.monospaced()).textInputAutocapitalization(.never).autocorrectionDisabled()
                LabeledContent("Google project", value: "garde-513820")
            } header: { Text("Gmail") } footer: {
                Text("Leave both blank to use the defaults. Testers are added in Google Cloud → Google Auth Platform → Audience (up to 100).")
            }
            Section {
                Button("Lock developer options", role: .destructive) { DeveloperMode.unlocked = false; onLock() }
            }
        }.listRowBackground(RowGlass()) }
    }
}
