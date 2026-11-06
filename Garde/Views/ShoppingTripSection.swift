import SwiftUI

struct ShoppingTripSection: View {
    let names: [String]
    let prices: [PriceBook.Entry]
    let profile: KitchenProfile?
    private var suggestion: PriceBook.StorePick? { PriceBook.bestStore(for: names, in: prices) }
    var body: some View {
        Section {
            if let profile, !profile.preferredStore.isEmpty {
                Label("Shopping at " + profile.preferredStore, systemImage: "storefront")
                if profile.allowExtraStore, let extra = extraStop(profile), extra.savings >= max(0, profile.minimumExtraStoreSavings) {
                    Text("An extra stop at \(extra.store) could save about \(extra.savings.formatted(.currency(code: "USD"))) on \(extra.count) comparable items.").font(.caption)
                }
            } else if let suggestion {
                Label(suggestion.store + " is cheapest for \(suggestion.cheapestFor) of \(suggestion.known) items with comparable price history.", systemImage: "storefront").font(.caption)
            }
            NavigationLink("Shopping preferences") { HouseholdMemoryView() }
        } header: { Text("Your trip") } footer: { Text("Estimates use your past receipts, before travel costs.") }
    }
    private func extraStop(_ profile: KitchenProfile) -> (store: String, savings: Double, count: Int)? {
        var savings: [String: Double] = [:], counts: [String: Int] = [:]
        for name in names {
            guard let entry = prices.first(where: { $0.key == PriceBook.key(name) }) else { continue }
            let grouped = Dictionary(grouping: entry.paid, by: \.store)
            let averages = grouped.mapValues { $0.map(\.price).reduce(0, +) / Double($0.count) }
            guard let home = averages.first(where: { $0.key.localizedCaseInsensitiveCompare(profile.preferredStore) == .orderedSame }) else { continue }
            for (store, price) in averages where store != home.key && store != "Unknown" && price < home.value {
                savings[store, default: 0] += home.value - price
                counts[store, default: 0] += 1
            }
        }
        guard let best = savings.max(by: { $0.value < $1.value }) else { return nil }
        return (best.key, best.value, counts[best.key] ?? 0)
    }
}
