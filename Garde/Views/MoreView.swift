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
            List { Group {
                Section {
                    NavigationLink { GardeSettingsView() } label: { Label("Settings: chef brain, iCloud, deals", systemImage: "gearshape") }
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
                    NavigationLink { ResetView() } label: { Label("Reset / start over", systemImage: "arrow.counterclockwise") }
                }
                Section {
                    NavigationLink { DeveloperOptionsView() } label: { Label("Developer options", systemImage: "lock") }
                } header: { Text("Your data") } footer: {
                    Text("Plain JSON, readable by any app or AI. Everything stays on this iPhone unless you share it.")
                }
                if let message { Section { Text(message) } }
            }.listRowBackground(RowGlass()) }
            .gardePage()
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
                                Text("\(r.date.formatted(date: .abbreviated, time: .omitted)) · \(r.items?.count ?? 0) items").font(.caption).foregroundStyle(.secondary)
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
    @State private var showText = false
    var body: some View {
        List { Group {
            if let data = receipt.image, let img = UIImage(data: data) {
                Section { Image(uiImage: img).resizable().scaledToFit() }
            }
            Section("Items") {
                ForEach(receipt.items ?? []) { i in
                    HStack { Text(i.name); Spacer(); if let p = i.price { Text(p, format: .currency(code: "USD")).foregroundStyle(.secondary) } }
                }
            }
            Section { DisclosureGroup("Raw text", isExpanded: $showText) { Text(receipt.rawText).font(.caption.monospaced()) } }
        }.listRowBackground(RowGlass()) }
        .gardePage()
        .navigationTitle(receipt.store.isEmpty ? "Receipt" : receipt.store)
    }
}

struct UsedUpView: View {
    @Query(filter: #Predicate<PantryItem> { $0.isUsedUp }, sort: \PantryItem.purchaseDate, order: .reverse) private var used: [PantryItem]
    @Environment(\.modelContext) private var context
    var body: some View {
        List { Group {
            if used.isEmpty { Text("Items you mark used up land here.").foregroundStyle(.secondary) }
            ForEach(used) { i in
                HStack { Text(i.name); Spacer(); Button("Restore") { i.isUsedUp = false }.buttonStyle(.borderless) }
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
    @State private var signedIn = GmailImporter.shared.isSignedIn
    @State private var working = false
    @State private var progress: (Int, Int)?
    @State private var message: String?
    @State private var confirmReimport = false

    private var gmailReceipts: [Receipt] { receipts.filter { $0.sourceID?.hasPrefix("gmail:") == true } }

    var body: some View {
        Form { Group {
            Section {
                if signedIn {
                    Label("Gmail connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Toggle("Import new receipts automatically", isOn: $auto)
                    Button { run(reimport: false) } label: { Label(working ? "Reading emails…" : "Check for new receipts", systemImage: "arrow.down.circle") }
                        .disabled(working)
                    if let (done, total) = progress, working, total > 0 {
                        ProgressView(value: Double(done), total: Double(total)) { Text("Email \(done) of \(total)").font(.caption) }
                    }
                    if let last = UserDefaults.standard.object(forKey: "gmail.lastSync") as? Date {
                        LabeledContent("Last checked", value: last.formatted(.relative(presentation: .named)))
                    }
                } else {
                    Button {
                        Task {
                            do { try await GmailImporter.shared.signIn(); signedIn = true; auto = true; message = nil; run(reimport: false) }
                            catch { message = error.localizedDescription }
                        }
                    } label: { Label("Connect Gmail", systemImage: "envelope.badge").font(.headline) }
                }
            } footer: {
                Text("Sign in with any Google account. Garde asks for read-only access and reads your order and receipt emails from the past year (Target, Walmart, Costco, BJ's, King Kullen, Stop & Shop, Fine Fare, Whole Foods, Sprouts, Trader Joe's, Wegmans, Instacart, Amazon and more) and keeps the food. The first import of a full year can take several minutes; keep Garde open, and it picks up where it left off if interrupted. Emails are read on this iPhone; nothing is sent anywhere else. Orders older than 3 weeks go into your history instead of your kitchen.")
            }

            if let message { Section { Text(message) } }

            if !gmailReceipts.isEmpty {
                Section("Imported from Gmail · \(gmailReceipts.count)") {
                    ForEach(gmailReceipts.prefix(30)) { r in
                        NavigationLink { ReceiptDetailView(receipt: r) } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(r.store).font(.body.weight(.medium))
                                    Text("\(r.date.formatted(date: .abbreviated, time: .omitted)) · \(r.items?.count ?? 0) items").font(.caption).foregroundStyle(.secondary)
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
                    Button("Re-read all Gmail receipts", systemImage: "arrow.clockwise") { confirmReimport = true }.disabled(working)
                    Button("Disconnect Gmail", role: .destructive) { GmailImporter.shared.signOut(); signedIn = false; auto = false }
                } footer: { Text("Re-reading deletes what was imported from Gmail and reads the past year again with the latest reader.") }
            }
            Section {
                Label("No Gmail? Share a receipt email from the Mail app to Garde, or snap a paper receipt in Scan.", systemImage: "square.and.arrow.up")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.listRowBackground(RowGlass()) }
        .gardePage()
        .navigationTitle("Gmail receipts")
        .confirmationDialog("Re-read all Gmail receipts?", isPresented: $confirmReimport, titleVisibility: .visible) {
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
                    : "Read \(r.emails) email\(r.emails == 1 ? "" : "s"): \(r.receipts) grocery receipt\(r.receipts == 1 ? "" : "s") (\(r.items) items)\(r.takeout > 0 ? ", \(r.takeout) takeout orders" : "")\(r.skipped > 0 ? ", \(r.skipped) skipped" : "")."
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
