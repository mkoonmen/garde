import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct MoreView: View {
    @State private var showAllergyCard = false
    @Environment(\.modelContext) private var context
    @State private var exportURL: URL?
    @State private var importing = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List { Group {
                Section {
                    NavigationLink { GardeSettingsView() } label: { Label("Settings: chef brain, iCloud, deals", systemImage: "gearshape") }
                    NavigationLink { SpicesView() } label: { Label("Spice rack", systemImage: "leaf") }
                    NavigationLink { BarView() } label: { Label("Bar & cellar", systemImage: "wineglass") }
                    NavigationLink { InsightsView() } label: { Label("Insights: cost & waste", systemImage: "chart.bar") }
                    NavigationLink { PriceBookView() } label: { Label("Price book", systemImage: "tag") }
                }
                Section {
                    NavigationLink { ProfileView() } label: { Label("Allergies & tastes", systemImage: "heart.text.square") }
                    Button { showAllergyCard = true } label: { Label("Allergy card for restaurants", systemImage: "person.text.rectangle") }
                    NavigationLink { ReceiptsView() } label: { Label("Receipts", systemImage: "receipt") }
                    NavigationLink { GmailSettingsView() } label: { Label("Email receipts (Gmail, iCloud)", systemImage: "envelope") }
                    NavigationLink { HouseholdMemoryView() } label: { Label("What the chef remembers", systemImage: "brain") }
                    NavigationLink { CookJournalView() } label: { Label("Cooking journal", systemImage: "book.closed") }
                    NavigationLink { UsedUpView() } label: { Label("Used-up history", systemImage: "clock.arrow.circlepath") }
                }
                Section {
                    Button("Export all data (JSON)", systemImage: "square.and.arrow.up") {
                        do { exportURL = try DataExport.exportJSON(context: context) } catch { message = error.localizedDescription }
                    }
                    if let exportURL { ShareLink("Share backup file", item: exportURL) }
                    Button("Import backup", systemImage: "square.and.arrow.down") { importing = true }
                    NavigationLink { ResetView() } label: { Label("Reset / start over", systemImage: "arrow.counterclockwise") }
                }
                Section {
                    NavigationLink { WhatsNewView() } label: { Label("What's new", systemImage: "sparkles") }
                    Link(destination: WhatsNew.feedbackURL) { Label("Send feedback (TestFlight)", systemImage: "envelope.badge") }
                } footer: { Text("Or take a screenshot anywhere in Garde and tap Share Beta Feedback.") }
                Section {
                    NavigationLink { DeveloperOptionsView() } label: { Label("Developer options", systemImage: "lock") }
                } header: { Text("Your data") } footer: {
                    Text("Plain JSON, readable by any app or AI. Everything stays on this iPhone unless you share it.")
                }
                if let message { Section { Text(message) } }

            let log = GmailImporter.log
            if !log.isEmpty {
                Section {
                    DisclosureGroup("What happened to each email (\(log.count))") {
                        ForEach(log.prefix(150)) { l in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(l.outcome).font(.caption.weight(.semibold))
                                    .foregroundStyle(l.outcome.hasPrefix("Imported") || l.outcome.hasPrefix("Takeout") ? Color.green : l.outcome.hasPrefix("Waiting") ? .orange : .secondary)
                                Text(l.from).font(.caption)
                                Text(l.subject).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                } footer: { Text("If a real grocery receipt was skipped, tell the developer which store it was from (TestFlight feedback) so Garde can learn it, then tap Re-read.") }
            }
            }.listRowBackground(RowGlass()) }
            .gardePage()
            .navigationTitle("More")
            .fullScreenCover(isPresented: $showAllergyCard) { AllergyCardView() }
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
        Form { Group {
            Section {
                TagEditor(tags: $profile.allergies, placeholder: "Add allergy (e.g. shellfish)")
                NavigationLink { NutAllergyView(profile: profile) } label: {
                    Label("Nut allergy with exceptions…", systemImage: "exclamationmark.shield")
                }
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
        }.listRowBackground(RowGlass()) }
        .gardePage()
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
        List { Group {
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
                                Text("\(r.date.formatted(date: .abbreviated, time: .omitted)) · \(Plural.items(r.items?.count ?? 0))").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let t = r.total { Text(t, format: .currency(code: "USD")) }
                        }
                    }
                }
                .onDelete { offsets in offsets.forEach { context.delete(receipts[$0]) } }
            }
        }.listRowBackground(RowGlass()) }
        .gardePage()
        .navigationTitle("Receipts")
    }
}

struct ReceiptDetailView: View {
    let receipt: Receipt
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showText = false
    @State private var editing: PantryItem?
    @State private var confirmDelete = false
    private var sortedItems: [PantryItem] { (receipt.items ?? []).sorted { $0.name < $1.name } }
    var body: some View {
        List { Group {
            if let data = receipt.image, let img = UIImage(data: data) {
                Section { Image(uiImage: img).resizable().scaledToFit() }
            }
            Section {
                LabeledContent("Store") { TextField("Store", text: Binding(get: { receipt.store }, set: { receipt.store = $0 })).multilineTextAlignment(.trailing) }
                LabeledContent("Total") {
                    TextField("–", value: Binding(get: { receipt.total }, set: { receipt.total = $0 }), format: .number.precision(.fractionLength(2)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
            }
            Section {
                ForEach(sortedItems) { i in
                    Button { editing = i } label: {
                        HStack { Text(i.name); Spacer(); if let p = i.price { Text(p, format: .currency(code: "USD")).foregroundStyle(.secondary) } }
                            .contentShape(.rect)
                    }.buttonStyle(.plain)
                }
                .onDelete { offsets in let list = sortedItems; for i in offsets where i < list.count { list[i].receipt = nil } }
            } header: { Text("Items") } footer: { Text("Tap to fix an item. Swipe to take it off this receipt (it stays in your kitchen).") }
            Section { DisclosureGroup("Raw text", isExpanded: $showText) { Text(receipt.rawText).font(.caption.monospaced()) } }
            Section {
                Button("Not a grocery receipt: remove it", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
        }.listRowBackground(RowGlass()) }
        .gardePage()
        .navigationTitle(receipt.store.isEmpty ? "Receipt" : receipt.store)
        .sheet(item: $editing) { ItemEditView(item: $0) }
        .confirmationDialog("Remove this receipt?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Remove receipt and its items from my kitchen", role: .destructive) { remove(items: true) }
            Button("Remove receipt only") { remove(items: false) }
        }
    }

    /// Leave the screen first, then delete, so nothing reads a deleted receipt.
    private func remove(items: Bool) {
        let r = receipt, its = receipt.items ?? []
        dismiss()
        Task { @MainActor in
            if items { its.forEach(context.delete) } else { its.forEach { $0.receipt = nil } }
            context.delete(r)
            try? context.save()
        }
    }
}

struct UsedUpView: View {
    @Query(filter: #Predicate<PantryItem> { $0.isUsedUp }, sort: \PantryItem.purchaseDate, order: .reverse) private var used: [PantryItem]
    @Environment(\.modelContext) private var context
    var body: some View {
        List { Group {
            if used.isEmpty { Text("Items you mark used up land here.").foregroundStyle(.secondary) }
            ForEach(used) { i in
                HStack {
                    NavigationLink { KitchenHistoryView(item: i) } label: { Text(i.name) }
                    Button("Restore") { i.restore() }.buttonStyle(.borderless)
                }
            }
            .onDelete { offsets in offsets.forEach { context.delete(used[$0]) } }
        }.listRowBackground(RowGlass()) }
        .gardePage()
        .navigationTitle("Used up")
    }
}

struct GmailSettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("gmail.autoImport") private var auto = false
    @Query(sort: \Receipt.date, order: .reverse) private var receipts: [Receipt]
    @State private var accounts = GmailImporter.shared.accounts
    @State private var addingIMAP = false
    private var signedIn: Bool { !accounts.isEmpty }
    @State private var working = false
    @State private var progress: (Int, Int)?
    @State private var message: String?
    @State private var confirmReimport = false

    private var gmailReceipts: [Receipt] { receipts.filter { $0.sourceID?.hasPrefix("gmail:") == true || $0.sourceID?.hasPrefix("imap:") == true } }

    var body: some View {
        Form { Group {
            Section {
                ForEach(accounts) { a in
                    HStack {
                        Image(systemName: a.kind == .gmail ? "envelope.fill" : "icloud.fill").foregroundStyle(Theme.copper)
                        VStack(alignment: .leading) {
                            Text(a.email).font(.body.weight(.medium)).lineLimit(1)
                            Text(a.label).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions { Button("Remove", role: .destructive) { GmailImporter.shared.remove(a); accounts = GmailImporter.shared.accounts } }
                }
                Button {
                    Task {
                        do { try await GmailImporter.shared.signIn(); accounts = GmailImporter.shared.accounts; auto = true; message = nil; run(reimport: false) }
                        catch { message = error.localizedDescription }
                    }
                } label: { Label(signedIn ? "Add another Gmail" : "Connect Gmail", systemImage: "envelope.badge") }
                Button { addingIMAP = true } label: { Label("Add iCloud Mail (or Yahoo)", systemImage: "icloud") }
                if signedIn {
                    Toggle("Import new receipts automatically", isOn: $auto)
                    Button { run(reimport: false) } label: { Label(working ? "Reading emails…" : "Check for new receipts", systemImage: "arrow.down.circle") }
                        .disabled(working)
                    if let (done, total) = progress, working, total > 0 {
                        ProgressView(value: Double(done), total: Double(total)) { Text("Email \(done) of \(total)").font(.caption) }
                    }
                    if let last = UserDefaults.standard.object(forKey: "gmail.lastSync") as? Date {
                        LabeledContent("Last checked", value: last.formatted(.relative(presentation: .named)))
                    }
                }
            } footer: {
                Text("Connect as many mailboxes as you like: several Gmail accounts, plus iCloud Mail (with an app-specific password) or Yahoo. Sign in with any Google account. Garde asks for read-only access and reads your order and receipt emails from the past year (Target, Walmart, Costco, BJ's, King Kullen, Stop & Shop, Fine Fare, Whole Foods, Sprouts, Trader Joe's, Wegmans, Instacart, Amazon and more) and keeps the food. The first import of a full year can take several minutes; keep Garde open, and it picks up where it left off if interrupted. Emails are read on this iPhone; nothing is sent anywhere else. Orders older than 3 weeks go into your history instead of your kitchen. DoorDash, Uber Eats and restaurant receipts become Takeout favorites.\n\nTesting Garde? Google only lets approved test accounts sign in for now, so send the developer the Gmail address you want to use first (through TestFlight feedback).")
            }

            if let message { Section { Text(message) } }

            let log = GmailImporter.log
            if !log.isEmpty {
                Section {
                    DisclosureGroup("What happened to each email (\(log.count))") {
                        ForEach(log.prefix(150)) { l in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(l.outcome).font(.caption.weight(.semibold))
                                    .foregroundStyle(l.outcome.hasPrefix("Imported") || l.outcome.hasPrefix("Takeout") ? Color.green : l.outcome.hasPrefix("Waiting") ? .orange : .secondary)
                                Text(l.from).font(.caption)
                                Text(l.subject).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                } footer: { Text("If a real grocery receipt was skipped, tell the developer which store it was from (TestFlight feedback) so Garde can learn it, then tap Re-read.") }
            }

            if !gmailReceipts.isEmpty {
                Section("Imported from email · \(gmailReceipts.count)") {
                    ForEach(gmailReceipts.prefix(30)) { r in
                        NavigationLink { ReceiptDetailView(receipt: r) } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(r.store).font(.body.weight(.medium))
                                    Text("\(r.date.formatted(date: .abbreviated, time: .omitted)) · \(Plural.items(r.items?.count ?? 0))").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let t = r.total { Text(t, format: .currency(code: "USD")) }
                            }
                        }
                    }
                }
            }

            if signedIn {
                Section {
                    Button("Re-read all email receipts", systemImage: "arrow.clockwise") { confirmReimport = true }.disabled(working)
                    Button("Disconnect all mailboxes", role: .destructive) { GmailImporter.shared.signOut(); accounts = []; auto = false }
                } footer: { Text("Re-reading deletes what was imported from email and reads the past year again with the latest reader. Swipe a mailbox to remove just that one.") }
            }
            Section {
                Label("No Gmail? Share a receipt email from the Mail app to Garde, or snap a paper receipt in Scan.", systemImage: "square.and.arrow.up")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.listRowBackground(RowGlass()) }
        .gardePage()
        .navigationTitle("Email receipts")
        .sheet(isPresented: $addingIMAP, onDismiss: { accounts = GmailImporter.shared.accounts }) { AddMailboxView { auto = true; run(reimport: false) } }
        .confirmationDialog("Re-read all email receipts?", isPresented: $confirmReimport, titleVisibility: .visible) {
            Button("Re-read", role: .destructive) { run(reimport: true) }
        } message: { Text("Removes \(gmailReceipts.count) imported receipts and their items, then imports them again.") }
    }

    private func run(reimport: Bool) {
        working = true; message = nil; progress = nil
        Task {
            do {
                let update: (Int, Int) -> Void = { d, t in Task { @MainActor in progress = (d, t) } }
                let r = reimport ? try await GmailImporter.shared.reimport(context: context, progress: update)
                                 : try await GmailImporter.shared.importNew(context: context, progress: update)
                message = r.emails == 0 ? "No new grocery emails."
                    : "Read \(r.emails) email\(r.emails == 1 ? "" : "s"): \(r.receipts) grocery receipt\(r.receipts == 1 ? "" : "s") (\(Plural.items(r.items)))\(r.takeout > 0 ? ", \(r.takeout) takeout orders" : "")\(r.skipped > 0 ? ", \(r.skipped) skipped" : "")."
                        + (r.waiting > 0 ? " \(r.waiting) takeout orders will be read once Apple Intelligence is ready." : "")
                        + (r.problems.isEmpty ? "" : "\n\nCouldn't read: " + r.problems.joined(separator: "; "))
            } catch { message = error.localizedDescription }
            working = false
        }
    }
}

/// For people allergic to some nuts but not others. Writes one allergy like
/// "Tree nuts except almonds, hazelnuts" (the allergy filter understands "except").
struct NutAllergyView: View {
    @Bindable var profile: KitchenProfile
    static let treeNuts = ["Almonds", "Hazelnuts", "Cashews", "Pistachios", "Walnuts", "Pecans", "Macadamia nuts",
                           "Brazil nuts", "Pine nuts", "Chestnuts"]
    @State private var safe: Set<String> = []
    @State private var peanutAllergy = false
    @State private var loaded = false

    var body: some View {
        Form { Group {
            Section {
                Toggle("Allergic to peanuts", isOn: $peanutAllergy)
            } footer: { Text("Peanuts are legumes, so they're handled separately from tree nuts.") }
            Section {
                ForEach(Self.treeNuts, id: \.self) { nut in
                    Toggle(isOn: Binding(get: { safe.contains(nut) }, set: { if $0 { safe.insert(nut) } else { safe.remove(nut) } })) {
                        HStack {
                            Text(nut)
                            Spacer()
                            Text(safe.contains(nut) ? "Safe" : "Allergic").font(.caption.weight(.semibold))
                                .foregroundStyle(safe.contains(nut) ? .green : .red)
                        }
                    }
                }
            } header: { Text("Tree nuts: turn on the ones you CAN eat") } footer: {
                Text("Everything left off is blocked, including anything that just says \"nuts\", \"mixed nuts\" or \"may contain nuts\" without naming the nut. Coconut is always treated as safe. Garde is a strong safety net, not a guarantee: always read labels.")
            }
            Section {
                Button("Save nut allergy") { save() }.font(.headline)
                if profile.allergies.contains(where: { $0.lowercased().hasPrefix("tree nut") }) {
                    Button("Remove tree nut allergy", role: .destructive) {
                        profile.allergies.removeAll { $0.lowercased().hasPrefix("tree nut") }
                    }
                }
            } footer: { Text("Saved as: \(summary)") }
        }.listRowBackground(RowGlass()) }
        .gardePage()
        .navigationTitle("Nut allergy")
        .onAppear(perform: load)
    }

    private var summary: String {
        safe.isEmpty ? "Tree nuts" : "Tree nuts except " + Self.treeNuts.filter(safe.contains).map { $0.lowercased() }.joined(separator: ", ")
    }

    private func load() {
        guard !loaded else { return }; loaded = true
        peanutAllergy = profile.allergies.contains { $0.lowercased().contains("peanut") }
        if let tn = profile.allergies.first(where: { $0.lowercased().hasPrefix("tree nut") }) {
            let okay = AllergenGuard.parse(tn).safe
            safe = Set(Self.treeNuts.filter { n in okay.contains { n.lowercased().hasPrefix($0) } })
        }
    }

    private func save() {
        profile.allergies.removeAll { let l = $0.lowercased(); return l.hasPrefix("tree nut") || l == "nuts" || l == "nut" || l.contains("peanut") }
        profile.allergies.append(summary)
        if peanutAllergy { profile.allergies.append("Peanuts") }
    }
}

/// Connect iCloud Mail (or Yahoo / another IMAP mailbox) with an app-specific password.
struct AddMailboxView: View {
    @Environment(\.dismiss) private var dismiss
    var onAdded: () -> Void
    @State private var provider = "iCloud"
    @State private var email = ""
    @State private var password = ""
    @State private var host = ""
    @State private var working = false
    @State private var error: String?

    private var server: String {
        switch provider { case "iCloud": "imap.mail.me.com"; case "Yahoo": "imap.mail.yahoo.com"; default: host.trimmingCharacters(in: .whitespaces) }
    }
    private var passwordHelp: URL {
        URL(string: provider == "Yahoo" ? "https://login.yahoo.com/account/security" : "https://account.apple.com/account/manage")!
    }

    var body: some View {
        NavigationStack {
            Form { Group {
                Section {
                    Picker("Mailbox", selection: $provider) { ForEach(["iCloud", "Yahoo", "Other"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
                    TextField(provider == "iCloud" ? "you@icloud.com" : "Email address", text: $email)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("App-specific password", text: $password)
                    if provider == "Other" {
                        TextField("IMAP server (e.g. imap.example.com)", text: $host).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                } footer: {
                    Text(provider == "Yahoo"
                         ? "Yahoo needs an app password: Account Security → Generate app password. Your normal password won't work."
                         : "Apple needs an app-specific password, not your Apple Account password: Sign-In and Security → App-Specific Passwords → +. Garde only reads mail, on this iPhone, and keeps the password in the Keychain.")
                }
                Section { Link(provider == "Yahoo" ? "Open Yahoo Account Security" : "Make an app-specific password", destination: passwordHelp) }
                if let error { Section { Text(error).foregroundStyle(.orange) } }
            }.listRowBackground(RowGlass()) }
            .gardePage()
            .navigationTitle("Add mailbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if working { ProgressView() } else {
                        Button("Add") { Task { await add() } }.disabled(!email.contains("@") || password.count < 8 || server.isEmpty)
                    }
                }
            }
        }
    }

    private func add() async {
        working = true; error = nil
        defer { working = false }
        do {
            try await GmailImporter.shared.addIMAP(email: email, password: password, host: server)
            dismiss(); onAdded()
        } catch { self.error = error.localizedDescription }
    }
}
