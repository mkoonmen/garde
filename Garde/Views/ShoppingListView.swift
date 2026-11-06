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
    @Query private var mealPlans: [MealPlanEntry]
    @Query private var profiles: [KitchenProfile]
    @Query private var everything: [PantryItem]
    @State private var prices: [PriceBook.Entry] = []
    @State private var addedUsuals = false
    @State private var shopping = false

    private var open: [ShoppingItem] { list.filter { !$0.isChecked && !$0.isDismissed } }
    private var done: [ShoppingItem] { list.filter { $0.isChecked && !$0.isDismissed } }
    private var grouped: [(FoodCategory, [ShoppingItem])] {
        let g = Dictionary(grouping: open, by: \.category)
        return ShoppingBrain.aisleOrder.compactMap { c in g[c].map { (c, $0) } }
    }

    var body: some View {
        NavigationStack {
            List { Group {
                ShoppingTripSection(names: open.map(\.name), prices: prices, profile: profiles.first)
                Section {
                    HStack {
                        TextField("Add item", text: $draft).focused($typing).submitLabel(.done).onSubmit(add)
                        Button("Add", systemImage: "plus.circle.fill", action: add).labelStyle(.iconOnly).font(.title2).disabled(draft.isEmpty)
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
                        ForEach(tripDeals.prefix(8)) { d in
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
                ShoppingBrain.refreshRunningLow(context: context)
                try? MealShopping.reconcile(context: context)
                prices = PriceBook.entries(everything)
                await refreshDeals()
            }
            .onChange(of: open.map(\.name)) { _, _ in deals.match(DealsService.terms(list: open, pantry: pantry)) }
        }
        .onChange(of: finishedItemIDs) { _, _ in ShoppingBrain.refreshRunningLow(context: context) }
        .onChange(of: stockSignature) { _, _ in
            ShoppingBrain.refreshRunningLow(context: context)
            try? MealShopping.reconcile(context: context)
        }
        .onChange(of: planSignature) { _, _ in try? MealShopping.reconcile(context: context) }
    }

    private var tripDeals: [DealsService.Deal] {
        guard let profile = profiles.first, !profile.preferredStore.isEmpty, !profile.allowExtraStore else { return deals.matchedDeals }
        return deals.matchedDeals.filter { $0.store.localizedCaseInsensitiveContains(profile.preferredStore) }
    }
    private var stockSignature: String { pantry.map { "\($0.id)/\($0.availableLabel)/\($0.ingredientName)" }.sorted().joined(separator: "|") }
    private var planSignature: String { mealPlans.map { "\($0.id)/\($0.isCooked)/" + $0.ingredients.joined(separator: "|") }.sorted().joined(separator: "|") }
    private var finishedItemIDs: [UUID] {
        everything.filter { $0.isUsedUp && !$0.wasTossed && !$0.isLeftover }.map(\.id)
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
        Button { withAnimation { item.isChecked.toggle(); item.wasAutoChecked = false } } label: {
            HStack {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle").foregroundStyle(item.isChecked ? .green : Theme.accent).font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name + (item.quantityNote.isEmpty ? "" : " · \(item.quantityNote)")).strikethrough(item.isChecked)
                    if !item.reason.isEmpty && item.reason != "Added by you" { Text(item.reason).font(.caption).foregroundStyle(.secondary) }
                    if item.isSpecificProduct { Text("Your usual product").font(.caption2).foregroundStyle(.secondary) }
                    if !item.mealNote.isEmpty { Text(item.mealNote).font(.caption).foregroundStyle(.secondary) }
                    if item.wasAutoChecked { Text("Matched to purchased groceries · tap to undo").font(.caption).foregroundStyle(.secondary) }
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
        .swipeActions { Button("Delete", systemImage: "trash", role: .destructive) { if item.planDemandKey.isEmpty { context.delete(item) } else { item.isDismissed = true } } }
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
    @State private var category: FoodCategory?
    @State private var store: String?
    @State private var expanded: Set<String> = []
    @Query(filter: #Predicate<ShoppingItem> { !$0.isChecked }) private var list: [ShoppingItem]
    @Query(filter: #Predicate<PantryItem> { !$0.isUsedUp }) private var pantry: [PantryItem]
    private var terms: [String] { DealsService.terms(list: list, pantry: pantry) }

    /// Sale items in aisle categories ("Meat", "Produce"…), not one long list per store.
    private var filtered: [DealsService.Deal] {
        deals.search(query).filter { d in
            (store == nil || d.store == store) && (category == nil || ShoppingBrain.guessCategory(d.name) == category)
        }
    }

    var body: some View {
        List { Group {
            Section {
                HStack {
                    TextField("ZIP code", text: $zipDraft).keyboardType(.numberPad).font(.headline)
                    Button("Update") { applyZip() }.buttonStyle(GardeProminent()).disabled(zipDraft.filter(\.isNumber).count != 5)
                }
                if deals.refreshing { HStack { ProgressView(); Text("Downloading this week's ads…").foregroundStyle(.secondary) } }
                if let e = deals.error { Text(e).font(.footnote).foregroundStyle(.orange) }
                if !deals.flyers.isEmpty {
                    Text("\(deals.flyers.count) grocery ads · \(deals.visible.count) sale items").font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text("Your area") }

            if !deals.all.isEmpty {
                // Filters: stores and aisles as chips.
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            chip("All stores", store == nil) { store = nil }
                            ForEach(deals.stores.filter { !deals.hiddenStores.contains($0) }, id: \.self) { s in chip(s, store == s) { store = store == s ? nil : s } }
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            chip("All aisles", category == nil) { category = nil }
                            ForEach(ShoppingBrain.aisleOrder, id: \.self) { c in chip(c.label, category == c) { category = category == c ? nil : c } }
                        }
                    }
                }

                if query.trimmingCharacters(in: .whitespaces).count >= 2 {
                    compareSection
                } else {
                    let byAisle = Dictionary(grouping: filtered) { ShoppingBrain.guessCategory($0.name) }
                    let order = ShoppingBrain.aisleOrder + FoodCategory.allCases.filter { !ShoppingBrain.aisleOrder.contains($0) }
                    ForEach(order.filter { byAisle[$0] != nil }, id: \.self) { c in
                        let items = (byAisle[c] ?? []).sorted { ($0.discountPercent ?? 0) > ($1.discountPercent ?? 0) }
                        let open = expanded.contains(c.rawValue) || category != nil
                        Section {
                            ForEach(items.prefix(open ? 300 : 3)) { DealRow(deal: $0) }
                            if items.count > 3 && category == nil {
                                Button(open ? "Show less" : "Show all \(items.count)") {
                                    withAnimation { if open { expanded.remove(c.rawValue) } else { expanded.insert(c.rawValue) } }
                                }.font(.subheadline.weight(.semibold))
                            }
                        } header: { Text("\(c.label) · \(items.count)") }
                    }
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
        .searchable(text: $query, prompt: "Search or compare: \"chicken\", \"eggs\"")
        .gardePage()
        .navigationTitle("Deals")
        .task { await deals.refresh(terms: terms) }
        .refreshable { await deals.refresh(terms: terms, force: true) }
    }

    /// Search = compare: the same thing across stores, cheapest first, with price per unit when the ad gives a size.
    @ViewBuilder private var compareSection: some View {
        let rows = filtered.map { (deal: $0, unit: DealCompare.unitPrice($0)) }
            .sorted { a, b in
                switch (a.unit, b.unit) {
                case let (x?, y?) where x.unit == y.unit: x.perUnit < y.perUnit
                default: (a.deal.price ?? .infinity) < (b.deal.price ?? .infinity)
                }
            }
        let priced = rows.compactMap(\.deal.price)
        if rows.isEmpty {
            Section { Text("Nothing on sale matches \"\(query)\" this week.").foregroundStyle(.secondary) }
        } else {
            Section {
                if let lo = priced.min(), let hi = priced.max(), hi > lo {
                    HStack {
                        VStack(alignment: .leading) { Text("Cheapest").font(.caption).foregroundStyle(.secondary); Text(lo, format: .currency(code: "USD")).font(.title3.bold()).foregroundStyle(.green) }
                        Spacer()
                        VStack { Text("Stores").font(.caption).foregroundStyle(.secondary); Text("\(Set(rows.map(\.deal.store)).count)").font(.title3.bold()) }
                        Spacer()
                        VStack(alignment: .trailing) { Text("Priciest").font(.caption).foregroundStyle(.secondary); Text(hi, format: .currency(code: "USD")).font(.title3.bold()) }
                    }
                }
                ForEach(Array(rows.prefix(60).enumerated()), id: \.element.deal.id) { i, r in
                    HStack(alignment: .center, spacing: 10) {
                        Text("\(i + 1)").font(.caption.weight(.bold)).foregroundStyle(i == 0 ? Color.green : .secondary).frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.deal.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                            HStack(spacing: 6) {
                                Text(r.deal.store).font(.caption).foregroundStyle(.secondary)
                                if i == 0 { Text("BEST").font(.caption2.weight(.heavy)).foregroundStyle(.green) }
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(r.deal.priceText).font(.subheadline.weight(.bold)).foregroundStyle(i == 0 ? Color.green : .primary)
                            if let u = r.unit { Text("\(u.perUnit.formatted(.currency(code: "USD")))/\(u.unit)").font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                }
            } header: { Text("Compare \"\(query)\" · \(rows.count)") } footer: {
                Text("Sorted by price per unit when the ad lists a size (oz, lb, ct), otherwise by price.")
            }
        }
    }

    private func chip(_ title: String, _ on: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(.bordered).tint(on ? Theme.copper : .secondary).font(.subheadline)
    }

    private func applyZip() {
        deals.zip = zipDraft
        Task { await deals.refresh(terms: terms, force: true) }
    }
}

/// Price per ounce / pound / count from an ad's name ("Chicken Thighs 3 lb", "Eggs 12 ct", "Yogurt 32 oz").
enum DealCompare {
    struct Unit { let perUnit: Double; let unit: String }
    static func unitPrice(_ d: DealsService.Deal) -> Unit? {
        guard let price = d.price, price > 0 else { return nil }
        let t = (d.name + " " + d.priceText).lowercased()
        if t.contains("/lb") || t.contains("per lb") || t.contains(" lb.") && !t.contains(" lb ") { return Unit(perUnit: price, unit: "lb") }
        if let m = t.firstMatch(of: /(\d+(?:\.\d+)?)\s*(oz|ounce|lb|pound|ct|count|pk|pack)\b/), let n = Double(m.1), n > 0 {
            switch m.2 {
            case "oz", "ounce": return Unit(perUnit: price / n * 16, unit: "lb")
            case "lb", "pound": return Unit(perUnit: price / n, unit: "lb")
            default: return Unit(perUnit: price / n, unit: "ea")
            }
        }
        return nil
    }
}

/// Copper button drawn by hand (system prominent buttons ignore the tint inside some glass lists and sheets).
struct GardeProminent: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(Theme.copper.opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.4), in: .capsule)
    }
}
