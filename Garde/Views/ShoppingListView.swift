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

    private var open: [ShoppingItem] { list.filter { !$0.isChecked } }
    private var done: [ShoppingItem] { list.filter(\.isChecked) }
    private var grouped: [(FoodCategory, [ShoppingItem])] {
        let g = Dictionary(grouping: open, by: \.category)
        return ShoppingBrain.aisleOrder.compactMap { c in g[c].map { (c, $0) } }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Add item", text: $draft).focused($typing).submitLabel(.done).onSubmit(add)
                        Button("Add", systemImage: "plus.circle.fill", action: add).labelStyle(.iconOnly).font(.title2).disabled(draft.isEmpty)
                    }
                }
                if deals.enabled && !deals.deals.isEmpty {
                    Section {
                        ForEach(deals.deals.prefix(8)) { d in DealRow(deal: d) }
                        NavigationLink("All \(deals.deals.count) deals") { DealsView() }
                    } header: {
                        HStack { Text("On sale near you"); Spacer(); if deals.refreshing { ProgressView().controlSize(.mini) } }
                    } footer: {
                        Text(deals.lastRefresh.map { "Weekly ads, checked \($0.formatted(.relative(presentation: .named)))." } ?? "")
                    }
                } else if deals.enabled && deals.refreshing {
                    Section { HStack { ProgressView(); Text("Checking this week's ads…").foregroundStyle(.secondary) } }
                } else if let e = deals.error {
                    Section { Label(e, systemImage: "wifi.exclamationmark").foregroundStyle(.secondary).font(.footnote) }
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
            }
            .gardePage()
            .navigationTitle("List")
            .toolbar {
                if !open.isEmpty {
                    ShareLink(item: shareText) { Label("Share", systemImage: "square.and.arrow.up") }
                }
            }
            .refreshable { ShoppingBrain.refreshRunningLow(context: context); await refreshDeals() }
            .task {
                if (deals.lastRefresh ?? .distantPast) < .now.addingTimeInterval(-6 * 3600) { await refreshDeals() }
            }
        }
    }

    /// What to look for: everything on the list, then staples that are close to running out.
    private func refreshDeals() async {
        let soon = pantry.filter { ($0.daysLeft ?? 99) <= 3 }.map(\.name)
        await deals.refresh(terms: open.map(\.name) + soon)
    }

    private func row(_ item: ShoppingItem) -> some View {
        Button { withAnimation { item.isChecked.toggle() } } label: {
            HStack {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle").foregroundStyle(item.isChecked ? .green : Theme.accent).font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name + (item.quantityNote.isEmpty ? "" : " · \(item.quantityNote)")).strikethrough(item.isChecked)
                    if !item.reason.isEmpty && item.reason != "Added by you" { Text(item.reason).font(.caption).foregroundStyle(.secondary) }
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
        context.insert(ShoppingItem(name: t.prefix(1).uppercased() + t.dropFirst(), category: ShoppingBrain.guessCategory(t)))
        draft = ""; typing = true
    }
}

struct DealRow: View {
    let deal: DealsService.Deal
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(deal.name).font(.subheadline.weight(.medium)).lineLimit(2)
                Text(deal.store).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(deal.priceText).font(.subheadline.weight(.bold)).foregroundStyle(.green).multilineTextAlignment(.trailing)
                if let s = deal.savings, s > 0 { Text("save \(s.formatted(.currency(code: "USD")))").font(.caption2).foregroundStyle(.secondary) }
                if let to = deal.validTo { Text("until \(to.formatted(.dateTime.weekday(.abbreviated)))").font(.caption2).foregroundStyle(.tertiary) }
            }
        }
    }
}

struct DealsView: View {
    @State private var deals = DealsService.shared
    @State private var newStore = ""
    var body: some View {
        List {
            let grouped = Dictionary(grouping: deals.deals, by: \.store).sorted { $0.key < $1.key }
            ForEach(grouped, id: \.key) { store, items in
                Section(store) { ForEach(items) { DealRow(deal: $0) } }
            }
            Section {
                Toggle("Check weekly ads", isOn: Binding(get: { deals.enabled }, set: { deals.enabled = $0 }))
                TextField("ZIP code", text: Binding(get: { deals.zip }, set: { deals.zip = $0 })).keyboardType(.numberPad)
                ForEach(deals.stores, id: \.self) { Text($0) }
                    .onDelete { deals.stores.remove(atOffsets: $0) }
                HStack {
                    TextField("Add a store", text: $newStore)
                    Button("Add") { if !newStore.isEmpty { deals.stores.append(newStore); newStore = "" } }
                }
            } header: { Text("Settings") } footer: {
                Text("Garde searches this week's grocery circulars for what's on your list and what's running low. Only the item word and ZIP code are sent; prices come from the stores' weekly ads and can change.")
            }
        }
        .gardePage()
        .navigationTitle("Deals")
    }
}
