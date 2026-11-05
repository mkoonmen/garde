import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct MoreView: View {
    @Environment(\.modelContext) private var context
    @State private var exportURL: URL?
    @State private var importing = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { GardeSettingsView() } label: { Label("Settings: chef brain, iCloud, TVs", systemImage: "gearshape") }
                    NavigationLink { SpicesView() } label: { Label("Spice rack", systemImage: "leaf") }
                    NavigationLink { BarView() } label: { Label("Bar & cellar", systemImage: "wineglass") }
                    NavigationLink { InsightsView() } label: { Label("Insights: cost & waste", systemImage: "chart.bar") }
                }
                Section {
                    NavigationLink { ProfileView() } label: { Label("Allergies & tastes", systemImage: "heart.text.square") }
                    NavigationLink { ReceiptsView() } label: { Label("Receipts", systemImage: "receipt") }
                    NavigationLink { GmailSettingsView() } label: { Label("Gmail receipts", systemImage: "envelope") }
                    NavigationLink { UsedUpView() } label: { Label("Used-up history", systemImage: "clock.arrow.circlepath") }
                }
                Section {
                    Button("Export all data (JSON)", systemImage: "square.and.arrow.up") {
                        do { exportURL = try DataExport.exportJSON(context: context) } catch { message = error.localizedDescription }
                    }
                    if let exportURL { ShareLink("Share backup file", item: exportURL) }
                    Button("Import backup", systemImage: "square.and.arrow.down") { importing = true }
                } header: { Text("Your data") } footer: {
                    Text("Plain JSON, readable by any app or AI. Everything stays on this iPhone unless you share it.")
                }
                if let message { Section { Text(message) } }
            }
            .navigationTitle("More")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    do { message = "Imported \(try DataExport.importJSON(from: url, context: context)) records." }
                    catch { message = "Import failed: \(error.localizedDescription)" }
                case .failure(let e): message = e.localizedDescription
                }
            }
        }
    }
}

struct ProfileView: View {
    @Query private var profiles: [KitchenProfile]
    var body: some View {
        if let p = profiles.first { ProfileForm(profile: p) } else { ProgressView() }
    }
}

private struct ProfileForm: View {
    @Bindable var profile: KitchenProfile
    var body: some View {
        Form {
            Section {
                TagEditor(tags: $profile.allergies, placeholder: "Add allergy (e.g. shellfish)")
            } header: { Text("Allergies") } footer: {
                Text("Hard rule. Recipes that mention these, or common foods made from them, are thrown out before you see them. Always double-check labels yourself.")
            }
            Section("Avoid") { TagEditor(tags: $profile.dislikes, placeholder: "Add something you don't like") }
            Section("Love") { TagEditor(tags: $profile.loves, placeholder: "Add a favorite") }
            Section("Diet notes") { TextField("e.g. no seed oils, mostly whole foods", text: $profile.dietNotes, axis: .vertical) }
            Section("Cooking") {
                Stepper("Cooking for \(profile.householdSize)", value: $profile.householdSize, in: 1...12)
                Picker("Skill", selection: $profile.skillLevel) {
                    ForEach(["Beginner", "Confident home cook", "Advanced / restaurant level"], id: \.self) { Text($0) }
                }
            }
            Section("Reminders") {
                Stepper("Warn \(profile.expirationWarningDays) day\(profile.expirationWarningDays == 1 ? "" : "s") before expiring",
                        value: $profile.expirationWarningDays, in: 1...7)
            }
        }
        .navigationTitle("Allergies & tastes")
    }
}

struct TagEditor: View {
    @Binding var tags: [String]
    let placeholder: String
    @State private var draft = ""
    var body: some View {
        ForEach(tags, id: \.self) { Text($0) }
            .onDelete { tags.remove(atOffsets: $0) }
        TextField(placeholder, text: $draft)
            .submitLabel(.done)
            .onSubmit {
                let t = draft.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty && !tags.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) { tags.append(t) }
                draft = ""
            }
    }
}

struct ReceiptsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Receipt.date, order: .reverse) private var receipts: [Receipt]

    private var thisMonth: Double {
        let cal = Calendar.current
        return receipts.filter { cal.isDate($0.date, equalTo: .now, toGranularity: .month) }.compactMap(\.total).reduce(0, +)
    }
    private var byStore: [(String, Double)] {
        Dictionary(grouping: receipts, by: { $0.store.isEmpty ? "Unknown" : $0.store })
            .map { ($0.key, $0.value.compactMap(\.total).reduce(0, +)) }
            .sorted { $0.1 > $1.1 }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("This month", value: thisMonth, format: .currency(code: "USD"))
                ForEach(byStore.prefix(5), id: \.0) { LabeledContent($0.0, value: $0.1, format: .currency(code: "USD")) }
            } header: { Text("Spending") }
            Section("Receipts") {
                if receipts.isEmpty { Text("Scanned receipts show up here.").foregroundStyle(.secondary) }
                ForEach(receipts) { r in
                    NavigationLink { ReceiptDetailView(receipt: r) } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(r.store.isEmpty ? "Receipt" : r.store).font(.body.weight(.medium))
                                Text("\(r.date.formatted(date: .abbreviated, time: .omitted)) · \(r.items?.count ?? 0) items").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let t = r.total { Text(t, format: .currency(code: "USD")) }
                        }
                    }
                }
                .onDelete { offsets in offsets.forEach { context.delete(receipts[$0]) } }
            }
        }
        .navigationTitle("Receipts")
    }
}

struct ReceiptDetailView: View {
    let receipt: Receipt
    @State private var showText = false
    var body: some View {
        List {
            if let data = receipt.image, let img = UIImage(data: data) {
                Section { Image(uiImage: img).resizable().scaledToFit() }
            }
            Section("Items") {
                ForEach(receipt.items ?? []) { i in
                    HStack { Text(i.name); Spacer(); if let p = i.price { Text(p, format: .currency(code: "USD")).foregroundStyle(.secondary) } }
                }
            }
            Section { DisclosureGroup("Raw text", isExpanded: $showText) { Text(receipt.rawText).font(.caption.monospaced()) } }
        }
        .navigationTitle(receipt.store.isEmpty ? "Receipt" : receipt.store)
    }
}

struct UsedUpView: View {
    @Query(filter: #Predicate<PantryItem> { $0.isUsedUp }, sort: \PantryItem.purchaseDate, order: .reverse) private var used: [PantryItem]
    @Environment(\.modelContext) private var context
    var body: some View {
        List {
            if used.isEmpty { Text("Items you mark used up land here.").foregroundStyle(.secondary) }
            ForEach(used) { i in
                HStack { Text(i.name); Spacer(); Button("Restore") { i.isUsedUp = false }.buttonStyle(.borderless) }
            }
            .onDelete { offsets in offsets.forEach { context.delete(used[$0]) } }
        }
        .navigationTitle("Used up")
    }
}

struct GmailSettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("gmail.clientID") private var clientID = ""
    @AppStorage("gmail.autoImport") private var auto = false
    @AppStorage("gmail.query") private var query = ""
    @State private var signedIn = GmailImporter.shared.isSignedIn
    @State private var working = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                TextField("Google iOS client ID", text: $clientID).textInputAutocapitalization(.never).autocorrectionDisabled().font(.footnote.monospaced())
            } header: { Text("Setup") } footer: {
                Text("One-time: in Google Cloud Console, enable the Gmail API, create an OAuth client of type iOS with bundle ID com.michaelkoonmen.garde, and add yourself as a test user. Paste the client ID here.")
            }
            Section {
                if signedIn {
                    Toggle("Import automatically", isOn: $auto)
                    Button(working ? "Importing…" : "Import now", systemImage: "arrow.down.circle") {
                        working = true
                        Task {
                            do { let n = try await GmailImporter.shared.importNew(context: context); message = n == 0 ? "No new grocery receipts." : "Added \(n) items." }
                            catch { message = error.localizedDescription }
                            working = false
                        }
                    }.disabled(working)
                    Button("Disconnect Gmail", role: .destructive) { GmailImporter.shared.signOut(); signedIn = false; auto = false }
                } else {
                    Button("Connect Gmail (read-only)", systemImage: "envelope.badge") {
                        Task {
                            do { try await GmailImporter.shared.signIn(); signedIn = true; auto = true; message = "Connected." }
                            catch { message = error.localizedDescription }
                        }
                    }.disabled(clientID.isEmpty)
                }
                if let last = UserDefaults.standard.object(forKey: "gmail.lastSync") as? Date {
                    LabeledContent("Last import", value: last.formatted(.relative(presentation: .named)))
                }
            } footer: {
                Text("Garde only reads emails that look like grocery receipts or orders. Email text is read on this iPhone; nothing goes to any other server.")
            }
            Section("Search (advanced)") {
                TextField("Gmail search", text: $query, prompt: Text("Default: grocery stores and order receipts"), axis: .vertical).font(.footnote.monospaced())
            }
            if let message { Section { Text(message) } }
        }
        .navigationTitle("Gmail receipts")
    }
}
