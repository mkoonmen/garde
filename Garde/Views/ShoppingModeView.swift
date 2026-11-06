import SwiftUI
import SwiftData

/// In the store: big rows in aisle order, tap to check off, screen stays on, running estimate from what you've paid before.
struct ShoppingModeView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ShoppingItem.createdAt) private var list: [ShoppingItem]
    let prices: [PriceBook.Entry]
    @State private var startedWith = 0
    @State private var inCart: Set<UUID> = []     // checked off during this trip: stay visible so a mis-tap can be undone

    private var open: [ShoppingItem] { list.filter { !$0.isChecked } }
    private var grouped: [(FoodCategory, [ShoppingItem])] {
        let shown = list.filter { !$0.isChecked || inCart.contains($0.id) }
        let g = Dictionary(grouping: shown, by: \.category).mapValues { $0.sorted { !$0.isChecked && $1.isChecked } }
        return ShoppingBrain.aisleOrder.compactMap { c in g[c].map { (c, $0) } }
            + g.filter { !ShoppingBrain.aisleOrder.contains($0.key) }.map { ($0.key, $0.value) }
    }
    private func estimate(_ name: String) -> Double? {
        let k = PriceBook.key(name)
        return prices.first { $0.key == k }?.last
    }

    var body: some View {
        NavigationStack {
            List {
                if open.isEmpty && inCart.isEmpty {
                    ContentUnavailableView("All done", systemImage: "checkmark.seal.fill", description: Text("Everything's in the cart."))
                }
                ForEach(grouped, id: \.0) { cat, items in
                    Section(cat.label) {
                        ForEach(items) { item in
                            Button {
                                withAnimation(.snappy) {
                                    item.isChecked.toggle()
                                    if item.isChecked { inCart.insert(item.id) }
                                }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                HStack {
                                    Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle").font(.title2)
                                        .foregroundStyle(item.isChecked ? Color.green : Theme.copper)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name).font(.title3.weight(.semibold)).strikethrough(item.isChecked).opacity(item.isChecked ? 0.5 : 1)
                                        if !item.quantityNote.isEmpty { Text(item.quantityNote).font(.caption).foregroundStyle(.secondary) }
                                    }
                                    Spacer()
                                    if let p = estimate(item.name) { Text(p, format: .currency(code: "USD")).foregroundStyle(.secondary).monospacedDigit() }
                                }
                                .padding(.vertical, 8).contentShape(.rect)
                            }.buttonStyle(.plain).listRowBackground(RowGlass())
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                let est = open.compactMap { estimate($0.name) }.reduce(0, +)
                HStack {
                    Text("\(startedWith - open.count) of \(startedWith) in the cart")
                    Spacer()
                    if est > 0 { Text("~\(est.formatted(.currency(code: "USD").precision(.fractionLength(0)))) to go") }
                }
                .font(.subheadline.weight(.semibold)).padding().background(.ultraThinMaterial)
            }
            .scrollContentBackground(.hidden)
            .background { GardeBackground() }
            .navigationTitle("Shopping")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { startedWith = open.count; UIApplication.shared.isIdleTimerDisabled = true }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        }
    }
}
