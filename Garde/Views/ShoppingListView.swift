import SwiftUI
import SwiftData

/// Smart list: learns your pace, adds what the week plan needs, grouped in store-walk order.
struct ShoppingListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ShoppingItem.createdAt) private var list: [ShoppingItem]
    @State private var draft = ""
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
            .navigationTitle("List")
            .toolbar {
                if !open.isEmpty {
                    ShareLink(item: shareText) { Label("Share", systemImage: "square.and.arrow.up") }
                }
            }
            .refreshable { ShoppingBrain.refreshRunningLow(context: context) }
        }
    }

    private func row(_ item: ShoppingItem) -> some View {
        Button { withAnimation { item.isChecked.toggle() } } label: {
            HStack {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle").foregroundStyle(item.isChecked ? .green : Theme.accent).font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name + (item.quantityNote.isEmpty ? "" : " · \(item.quantityNote)")).strikethrough(item.isChecked)
                    if !item.reason.isEmpty && item.reason != "Added by you" { Text(item.reason).font(.caption).foregroundStyle(.secondary) }
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
