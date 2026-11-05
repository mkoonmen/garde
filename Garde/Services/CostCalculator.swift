import Foundation

/// Money math: what a dinner cost and what got thrown away.
enum CostCalculator {
    /// Rough cost of a recipe from what you paid for matching kitchen items.
    /// Uses the per-unit price of each matched item, one unit per ingredient line (an estimate, not an invoice).
    static func estimate(ingredients: [String], items: [PantryItem]) -> (total: Double, matched: Int) {
        var total = 0.0, matched = 0
        let priced = items.filter { ($0.price ?? 0) > 0 }
        for line in ingredients.map({ $0.lowercased() }) {
            guard let item = priced
                .filter({ line.contains(ShoppingBrain.key($0.name)) || ShoppingBrain.key($0.name).split(separator: " ").contains(where: { $0.count > 3 && line.contains($0) }) })
                .max(by: { $0.purchaseDate < $1.purchaseDate }),
                  let price = item.price else { continue }
            let perUnit = price / max(item.quantity, 1)
            total += min(perUnit, price)
            matched += 1
        }
        return (total, matched)
    }

    struct WasteReport {
        var tossedCount: Int
        var tossedValue: Double
        var eatenCount: Int
        var topTossed: [(String, Int)]
        var wasteRate: Double { tossedCount + eatenCount == 0 ? 0 : Double(tossedCount) / Double(tossedCount + eatenCount) }
    }

    static func waste(items: [PantryItem], since: Date) -> WasteReport {
        let done = items.filter { $0.isUsedUp && ($0.usedUpDate ?? $0.purchaseDate) >= since }
        let tossed = done.filter(\.wasTossed)
        let top = Dictionary(grouping: tossed, by: { $0.name }).map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }.prefix(5)
        return WasteReport(tossedCount: tossed.count,
                           tossedValue: tossed.compactMap(\.price).reduce(0, +),
                           eatenCount: done.count - tossed.count,
                           topTossed: Array(top))
    }
}
