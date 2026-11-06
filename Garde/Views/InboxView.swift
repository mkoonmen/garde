import SwiftUI
import SwiftData

/// Recipes shared to Garde from other apps. Each one is read, checked for allergens,
/// and compared with the pantry so you can see what you'd need to buy.
struct InboxView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [KitchenProfile]
    @Query(filter: #Predicate<PantryItem> { !$0.isUsedUp }) private var pantry: [PantryItem]

    @State private var items: [InboxItem] = RecipeInbox.load()
    /// Kept for the whole app session so reopening the inbox doesn't re-download and re-read everything.
    @MainActor private static var cache: [UUID: Result<RecipeImporter.Imported, Error>] = [:]
    @State private var results: [UUID: Result<RecipeImporter.Imported, Error>] = InboxView.cache
    @State private var pendingReceipt: PendingReceipt?
    struct PendingReceipt: Identifiable { let id: UUID; let item: InboxItem; let scan: ParsedScan; let text: String }
    @State private var working: Set<UUID> = []
    @State private var receiptNote: String?
    @State private var pasted = ""
    @State private var declinedReceipts: Set<UUID> = []
    @State private var shownReceiptID: UUID?

    var body: some View {
        List { Group {
            Section {
                HStack {
                    TextField("Paste a recipe link or text", text: $pasted, axis: .vertical).lineLimit(1...4)
                    Button("Add", systemImage: "plus.circle.fill") { addPasted() }.labelStyle(.iconOnly).font(.title2)
                        .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                PasteButton(payloadType: String.self) { strings in
                    if let s = strings.first { pasted = s; addPasted() }
                }.labelStyle(.titleAndIcon)
            } footer: { Text("Or in any app: Share → Garde.") }
            if let receiptNote { Section { Label(receiptNote, systemImage: "checkmark.circle.fill").foregroundStyle(.green) } }
            if items.isEmpty {
                ContentUnavailableView("Nothing shared yet", systemImage: "square.and.arrow.down",
                                       description: Text("In TikTok, Instagram, Safari or Photos, tap Share → Garde. The recipe shows up here."))
            }
            ForEach(items) { item in
                Section(item.url.flatMap { URL(string: $0)?.host } ?? (item.imageFile != nil ? "Photo" : "Shared text")) {
                    row(item)
                }
            }
        }.listRowBackground(RowGlass()) }
        .gardePage()
        .navigationTitle("Shared recipes")
        .task { await processAll() }
        .sheet(item: $pendingReceipt, onDismiss: {
            // Closed without adding: don't keep popping that receipt up; it stays in the list to review or remove.
            if let id = shownReceiptID, RecipeInbox.load().contains(where: { $0.id == id }) { declinedReceipts.insert(id) }
            shownReceiptID = nil
        }) { p in
            ScanReviewView(scan: p.scan, isReceipt: true, rawText: p.text, image: nil) {
                RecipeInbox.remove(p.item.id)
                items.removeAll { $0.id == p.item.id }
                receiptNote = "Added groceries from a shared receipt\(p.scan.store.isEmpty ? "" : " (\(p.scan.store))")."
            }
        }
        .refreshable { items = RecipeInbox.load(); await processAll() }
    }

    @ViewBuilder private func row(_ item: InboxItem) -> some View {
        if working.contains(item.id) {
            HStack { ProgressView(); Text("Reading the recipe…").foregroundStyle(.secondary) }
        } else if let result = results[item.id] {
            switch result {
            case .success(let imp):
                let r = imp.recipe
                // Re-checked every time, so a changed allergy list applies to recipes read earlier too.
                let allergens = Array(Set(imp.allergens + AllergenGuard.violations(in: [r.title] + r.ingredients + r.steps, allergies: profiles.flatMap(\.allergies)))).sorted()
                if !allergens.isEmpty {
                    Label("Contains \(allergens.joined(separator: ", ")), which you're allergic to.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).font(.subheadline.weight(.semibold))
                }
                NavigationLink {
                    RecipeDetailView(title: r.title, summary: r.summary, minutes: r.minutes, servings: r.servings,
                                     ingredients: r.ingredients, steps: r.steps, idea: r)
                } label: { RecipeRow(title: r.title, summary: r.summary, minutes: r.minutes) }
                if !imp.missing.isEmpty {
                    DisclosureGroup("You'd need \(imp.missing.count) thing\(imp.missing.count == 1 ? "" : "s")") {
                        ForEach(imp.missing, id: \.self) { Text($0).font(.subheadline) }
                    }
                }
                HStack {
                    Button("Save", systemImage: "bookmark") {
                        context.insert(SavedRecipe(title: r.title, summary: r.summary, minutes: r.minutes, servings: r.servings,
                                                   ingredients: r.ingredients, steps: r.steps))
                        done(item)
                    }.disabled(!allergens.isEmpty)
                    Spacer()
                    if !imp.missing.isEmpty && allergens.isEmpty {
                        Button("Add missing to List", systemImage: "cart.badge.plus") {
                            let safe = imp.missing.filter { AllergenGuard.violations(in: [$0], allergies: profiles.flatMap(\.allergies)).isEmpty }
                            ShoppingBrain.add(needToBuy: safe.map(shortName), for: r.title, day: .now, context: context)
                        }
                    }
                }.buttonStyle(.borderless)
                Button("Dismiss", role: .destructive) { done(item) }.font(.footnote)
            case .failure(let e):
                Text(e.localizedDescription).foregroundStyle(.secondary)
                HStack {
                    Button("Try again") { Task { await process(item) } }
                    Spacer()
                    Button("Remove", role: .destructive) { done(item) }
                }.buttonStyle(.borderless)
            }
        } else if looksLikeReceipt(item) {
            HStack {
                Button("Review this receipt") { Task { declinedReceipts.remove(item.id); _ = await importIfReceipt(item) } }
                Spacer()
                Button("Remove", role: .destructive) { done(item) }
            }.buttonStyle(.borderless)
        } else {
            Button("Read this recipe") { Task { await process(item) } }
        }
    }

    /// "2 cups baby spinach, washed" → "baby spinach"
    private func shortName(_ line: String) -> String {
        var s = line.lowercased()
        s = s.replacing(/^[\d\s\/½¼¾⅓⅔.\-]+/, with: "")
        s = s.replacing(/^(cups?|tablespoons?|tbsps?|teaspoons?|tsps?|lbs?|pounds?|oz|ounces?|grams?|g|kg|cans?|cloves?|pinch|bunch(es)?|sprigs?|slices?|large|small|medium)\b\.?\s*(of\s+)?/, with: "")
        return s.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? line
    }

    private func addPasted() {
        let t = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let link = t.firstMatch(of: /https?:\/\/\S+/).map { String($0.0) }
        RecipeInbox.add(url: link, text: link == nil || t.count > (link?.count ?? 0) + 5 ? t : nil)
        pasted = ""
        items = RecipeInbox.load()
        Task { await processAll() }
    }

    private func processAll() async {
        for item in items where results[item.id] == nil && !declinedReceipts.contains(item.id) {
            if looksLikeReceipt(item) {
                if pendingReceipt == nil { _ = await importIfReceipt(item) }
                continue   // a receipt is never read as a recipe
            }
            await process(item)
        }
    }

    /// A shared receipt email (from Mail) goes straight into the kitchen instead of being read as a recipe.
    private func looksLikeReceipt(_ item: InboxItem) -> Bool {
        guard let text = item.text else { return false }
        let lower = text.lowercased()
        let priceLines = text.split(separator: "\n").filter { $0.contains(/\d+\.\d{2}\s*$/) }.count
        return priceLines >= 3 && (lower.contains("total") || lower.contains("order") || lower.contains("receipt"))
    }

    private func importIfReceipt(_ item: InboxItem) async -> Bool {
        guard looksLikeReceipt(item), let text = item.text else { return false }
        let scan = await ChefAI().parseScan(text: String(text.prefix(6000)), labels: [])
        guard !scan.items.isEmpty else { return false }
        // Show it for review first: a recipe post with prices shouldn't silently become groceries.
        shownReceiptID = item.id
        pendingReceipt = PendingReceipt(id: item.id, item: item, scan: scan, text: text)
        return true
    }

    private func process(_ item: InboxItem) async {
        working.insert(item.id)
        defer { working.remove(item.id) }
        do { results[item.id] = .success(try await RecipeImporter.importItem(item, profile: profiles.first, pantry: pantry)) }
        catch { results[item.id] = .failure(error) }
        if case .success = results[item.id] { Self.cache[item.id] = results[item.id] }
    }

    private func done(_ item: InboxItem) {
        RecipeInbox.remove(item.id)
        withAnimation { items.removeAll { $0.id == item.id }; results[item.id] = nil }
    }
}
