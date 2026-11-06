import SwiftUI
import SwiftData

/// Smart list: learns your pace, adds what the week plan needs, grouped in store-walk order.
struct ShoppingListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ShoppingItem.createdAt) private var list: [ShoppingItem]
    @State private var draft = ""
    @State private var deals = DealsService.shared
    @Query(filter: #Predicate<PantryItem> { !$0.isUsedUp }) private var pantry: [PantryItem]
    @FocusState private var typing: Bool
    @Query private var everything: [PantryItem]
    @State private var prices: [PriceBook.Entry] = []
    @State private var addedUsuals = false
    @State private var shopping = false

    private var open: [ShoppingItem] { list.filter { !$0.isChecked } }
    private var done: [ShoppingItem] { list.filter(\.isChecked) }
    private var grouped: [(FoodCategory, [ShoppingItem])] {
        let g = Dictionary(grouping: open, by: \.category)
        return ShoppingBrain.aisleOrder.compactMap { c in g[c].map { (c, $0) } }
    }

    var body: some View {
        NavigationStack {
            List { Group {
                Section {
                    HStack {
                        TextField("Add item", text: $draft).focused($typing).submitLabel(.done).onSubmit(add)
                        Button("Add", systemImage: "plus.circle.fill", action: add).labelStyle(.iconOnly).font(.title2).disabled(draft.isEmpty)
                    }
                    if let pick = PriceBook.bestStore(for: open.map(\.name), in: prices) {
                        Label {
                            Text("Shop at **\(pick.store)**: cheapest for \(pick.cheapestFor) of \(pick.known) items you've bought before\(pick.savings >= 1 ? ", about \(pick.savings.formatted(.currency(code: "USD").precision(.fractionLength(0)))) less" : "").")
                                .font(.subheadline)
                        } icon: { Image(systemName: "storefront").foregroundStyle(Theme.copper) }
                    }
                    let usuals = missingUsuals
                    if !usuals.isEmpty && !addedUsuals {
                        Button {
                            addedUsuals = true
                            withAnimation {
                                for n in usuals { context.insert(ShoppingItem(name: n, category: ShoppingBrain.guessCategory(n), reason: "One of your usuals")) }
                            }
                            try? context.save()
                        } label: {
                            Label("Add my usuals (\(usuals.count)): \(usuals.prefix(3).joined(separator: ", "))\(usuals.count > 3 ? "…" : "")",
                                  systemImage: "arrow.triangle.2.circlepath").font(.subheadline).lineLimit(2)
                        }
                    }
                }
                if deals.enabled && !deals.visible.isEmpty {
                    Section {
                        if deals.matchedDeals.isEmpty {
                            Text("Nothing on your list is on sale this week.").font(.subheadline).foregroundStyle(.secondary)
                        }
                        ForEach(deals.matchedDeals.prefix(8)) { d in
                            // Only compare like with like: every word you buy it as must be in the deal, and not per-pound deals.
                            let perLb = d.name.lowercased().contains("/lb") || d.name.lowercased().contains("per lb") || d.priceText.lowercased().contains("lb")
                            DealRow(deal: d, usual: perLb ? nil : prices.first { !$0.key.isEmpty && ShoppingBrain.sameItem(list: $0.key, bought: d.name) }?.average)
                        }
                        NavigationLink("Browse all \(deals.visible.count) sale items") { DealsView() }
                    } header: {
                        HStack { Text("On sale near you"); Spacer(); if deals.refreshing { ProgressView().controlSize(.mini) } }
                    } footer: {
                        Text(deals.lastRefresh.map { "Weekly ads, checked \($0.formatted(.relative(presentation: .named)))." } ?? "")
                    }
                } else if deals.enabled && deals.refreshing {
                    Section { HStack { ProgressView(); Text("Checking this week's ads…").foregroundStyle(.secondary) } }
                } else if let e = deals.error {
                    Section {
                        Label(e, systemImage: "tag.slash").foregroundStyle(.secondary).font(.footnote)
                        NavigationLink("Deals settings") { DealsView() }
                    }
                }
                if open.isEmpty {
                    ContentUnavailableView("List is clear", systemImage: "checklist",
                                           description: Text("Garde adds things as you run low, and the week plan adds what dinners need."))
                }
                ForEach(grouped, id: \.0) { category, items in
                    Section(category.label) {
                        ForEach(items) { item in row(item) }
                    }
                }
                if !done.isEmpty {
                    Section {
                        ForEach(done) { item in row(item) }
                        Button("Clear checked", role: .destructive) { done.forEach { context.delete($0) } }
                    } header: { Text("In the cart") }
                }
            }.listRowBackground(RowGlass()) }
            .gardePage()
            .navigationTitle("List")
            .toolbar {
                if !open.isEmpty {
                    Button("Shop", systemImage: "cart") { shopping = true }
                    ShareLink(item: shareText) { Label("Share", systemImage: "square.and.arrow.up") }
                }
            }
            .fullScreenCover(isPresented: $shopping) { ShoppingModeView(prices: prices) }
            .refreshable { ShoppingBrain.refreshRunningLow(context: context); await forceRefreshDeals() }
            .task {
                prices = PriceBook.entries(everything)
                await refreshDeals()
            }
        }
    }

    /// What to look for: everything on the list, then staples that are close to running out.
    private func refreshDeals() async {
        await deals.refresh(terms: DealsService.terms(list: open, pantry: pantry))
    }
    private func forceRefreshDeals() async {
        await deals.refresh(terms: DealsService.terms(list: open, pantry: pantry), force: true)
    }

    /// Things you buy again and again (3+ times in the last 2 months) that aren't in the kitchen or on the list.
    private var missingUsuals: [String] {
        let since = Date.now.addingTimeInterval(-60 * 86_400)
        let onList = Set(open.map { PriceBook.key($0.name) })
        let have = Set(pantry.map { PriceBook.key($0.name) })
        return prices.filter { e in e.paid.filter { $0.date >= since }.count >= 3 && !onList.contains(e.key) && !have.contains(e.key) }
            .prefix(8).map(\.name)
    }

    private func row(_ item: ShoppingItem) -> some View {
        Button { withAnimation { item.isChecked.toggle() } } label: {
            HStack {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle").foregroundStyle(item.isChecked ? .green : Theme.accent).font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name + (item.quantityNote.isEmpty ? "" : " · \(item.quantityNote)")).strikethrough(item.isChecked)
                    if !item.reason.isEmpty && item.reason != "Added by you" { Text(item.reason).font(.caption).foregroundStyle(.secondary) }
                    if !item.isChecked, let p = PriceBook.hint(for: item.name, in: prices) {
                        Text(p).font(.caption2).foregroundStyle(.secondary)
                    }
                    if let d = deals.deals(for: item.name).first {
                        Label("\(d.priceText) at \(d.store)", systemImage: "tag.fill").font(.caption.weight(.semibold)).foregroundStyle(.green)
                    }
                }
            }.contentShape(.rect)
        }
        .buttonStyle(.plain)
        .swipeActions { Button("Delete", systemImage: "trash", role: .destructive) { context.delete(item) } }
    }

    private var shareText: String {
        grouped.map { c, items in "\(c.label.uppercased())\n" + items.map { "☐ \($0.name)" }.joined(separator: "\n") }.joined(separator: "\n\n")
    }

    private func add() {
        let t = draft.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        // "eggs, milk and 2 lb chicken" adds three items; amounts go in the note.
        let lines = QuickAdd.parse(t)
        if lines.count > 1 {
            for l in lines {
                let note = l.unit == "each" && l.quantity == 1 ? "" : "\(l.quantity.formatted()) \(l.unit == "each" ? "" : l.unit)".trimmingCharacters(in: .whitespaces)
                context.insert(ShoppingItem(name: l.name, category: l.category, quantityNote: note))
            }
        } else {
            context.insert(ShoppingItem(name: t.prefix(1).uppercased() + t.dropFirst(), category: ShoppingBrain.guessCategory(t)))
        }
        draft = ""; typing = true
    }
}

struct DealRow: View {
    let deal: DealsService.Deal
    var usual: Double? = nil      // what you normally pay, from your receipts
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(deal.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text([deal.brand, deal.store].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(deal.priceText).font(.subheadline.weight(.bold)).foregroundStyle(.green).multilineTextAlignment(.trailing)
                if let usual, let p = deal.price, usual > p * 1.05 {
                    Text("you usually pay \(usual.formatted(.currency(code: "USD")))").font(.caption2.weight(.semibold)).foregroundStyle(Theme.copper)
                }
                if let to = deal.validTo { Text("thru \(to.formatted(.dateTime.weekday(.abbreviated)))").font(.caption2).foregroundStyle(.tertiary) }
            }
        }
    }
}

struct DealsView: View {
    @State private var deals = DealsService.shared
    @State private var query = ""
    @State private var zipDraft = DealsService.shared.zip
    @Query(filter: #Predicate<ShoppingItem> { !$0.isChecked }) private var list: [ShoppingItem]
    @Query(filter: #Predicate<PantryItem> { !$0.isUsedUp }) private var pantry: [PantryItem]
    private var terms: [String] { DealsService.terms(list: list, pantry: pantry) }

    var body: some View {
        List { Group {
            Section {
                HStack {
                    TextField("ZIP code", text: $zipDraft).keyboardType(.numberPad).font(.headline)
                    Button("Update") { applyZip() }.buttonStyle(.borderedProminent).tint(Theme.copper).disabled(zipDraft.filter(\.isNumber).count != 5)
                }
                if deals.refreshing { HStack { ProgressView(); Text("Downloading this week's ads…").foregroundStyle(.secondary) } }
                if let e = deals.error { Text(e).font(.footnote).foregroundStyle(.orange) }
                if !deals.flyers.isEmpty {
                    Text("\(deals.flyers.count) grocery ads · \(deals.all.count) sale items").font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text("Your area") }

            if !deals.all.isEmpty {
                let results = deals.search(query)
                let grouped = Dictionary(grouping: results, by: \.store).sorted { $0.key < $1.key }
                ForEach(grouped, id: \.key) { store, items in
                    Section("\(store) · \(items.count)") { ForEach(items.prefix(query.isEmpty ? 40 : 200)) { DealRow(deal: $0) } }
                }
                Section {
                    ForEach(deals.stores, id: \.self) { store in
                        Toggle(store, isOn: Binding(get: { !deals.hiddenStores.contains(store) },
                                                    set: { on in
                                                        if on { deals.hiddenStores.removeAll { $0 == store } } else { deals.hiddenStores.append(store) }
                                                    }))
                    }
                } header: { Text("Stores") } footer: {
                    Text("Weekly ads near your ZIP. Turn off stores you don't shop at. Prices come from each store's circular and can change.")
                }
            }
            Section { Toggle("Show deals", isOn: Binding(get: { deals.enabled }, set: { deals.enabled = $0 })) }
        }.listRowBackground(RowGlass()) }
        .searchable(text: $query, prompt: "Search sale items")
        .gardePage()
        .navigationTitle("Deals")
        .task { await deals.refresh(terms: terms) }
        .refreshable { await deals.refresh(terms: terms, force: true) }
    }

    private func applyZip() {
        deals.zip = zipDraft
        Task { await deals.refresh(terms: terms, force: true) }
    }
}
