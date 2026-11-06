import SwiftUI
import SwiftData

/// In the store: big rows in aisle order, tap to check off, screen stays on, running estimate from what you've paid before.
struct ShoppingModeView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ShoppingItem.createdAt) private var list: [ShoppingItem]
    let prices: [PriceBook.Entry]
    @State private var startedWith = 0

    private var open: [ShoppingItem] { list.filter { !$0.isChecked } }
    private var grouped: [(FoodCategory, [ShoppingItem])] {
        let g = Dictionary(grouping: open, by: \.category)
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
                if open.isEmpty {
                    ContentUnavailableView("All done", systemImage: "checkmark.seal.fill", description: Text("Everything's in the cart."))
                }
                ForEach(grouped, id: \.0) { cat, items in
                    Section(cat.label) {
                        ForEach(items) { item in
                            Button {
                                withAnimation(.snappy) { item.isChecked = true }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                HStack {
                                    Image(systemName: "circle").font(.title2).foregroundStyle(Theme.copper)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name).font(.title3.weight(.semibold))
                                        if !item.quantityNote.isEmpty { Text(item.quantityNote).font(.caption).foregroundStyle(.secondary) }
                                    }
                                    Spacer()
                                    if let p = estimate(item.name) { Text(p, format: .currency(code: "USD")).foregroundStyle(.secondary).monospacedDigit() }
                                }
                                .padding(.vertical, 8).contentShape(.rect)
                            }.buttonStyle(.plain)
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
            .navigationTitle("Shopping")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { startedWith = open.count; UIApplication.shared.isIdleTimerDisabled = true }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        }
    }
}
