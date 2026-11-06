import Foundation

/// What you've paid for things, from receipts and scans: last price, lowest, and the cheapest store.
enum PriceBook {
    struct Entry: Identifiable {
        var id: String { key }
        let key: String
        let name: String
        let paid: [(date: Date, store: String, price: Double)]
        var last: Double { paid.first?.price ?? 0 }
        var lowest: Double { paid.map(\.price).min() ?? 0 }
        var average: Double { paid.isEmpty ? 0 : paid.map(\.price).reduce(0, +) / Double(paid.count) }
        var cheapestStore: String? {
            let byStore = Dictionary(grouping: paid, by: \.store).mapValues { $0.map(\.price).reduce(0, +) / Double($0.count) }
            return byStore.count > 1 ? byStore.min { $0.value < $1.value }?.key : nil
        }
        /// Positive when the last price is above your average (prices going up).
        var trend: Double { paid.count < 2 || average == 0 ? 0 : (last - average) / average }
    }

    /// "Organic Baby Spinach 5oz" and "baby spinach" land on the same key.
    static func key(_ name: String) -> String {
        let drop: Set<String> = ["organic", "org", "fresh", "large", "small", "medium", "lg", "sm", "the", "of", "and", "each", "ct", "pack", "pk", "lb", "oz", "gal", "gallon", "qt", "quart"]
        let words = name.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !drop.contains($0) && !$0.allSatisfy(\.isNumber) && !($0.first!.isNumber && $0.count <= 5) }
        return words.map { $0.count > 3 && $0.hasSuffix("s") && !$0.hasSuffix("ss") ? String($0.dropLast()) : $0 }.joined(separator: " ")
    }

    /// Receipt lines are totals; for countable items, compare the price of one.
    static func unitPrice(_ i: PantryItem) -> Double {
        let p = i.price ?? 0
        return i.unit == "each" && i.quantity > 1 && i.quantity == i.quantity.rounded() ? p / i.quantity : p
    }

    static func entries(_ items: [PantryItem]) -> [Entry] {
        let priced = items.filter { ($0.price ?? 0) > 0 }
        return Dictionary(grouping: priced) { key($0.name) }
            .filter { !$0.key.isEmpty }
            .map { k, list in
                let sorted = list.sorted { $0.purchaseDate > $1.purchaseDate }
                return Entry(key: k, name: sorted[0].name,
                             paid: sorted.map { (date: $0.purchaseDate, store: $0.store ?? "Unknown", price: unitPrice($0)) })
            }
            .sorted { $0.paid.count == $1.paid.count ? $0.name < $1.name : $0.paid.count > $1.paid.count }
    }

    /// Short hint for a shopping-list row: "last $3.49 · cheapest at ALDI".
    static func hint(for name: String, in entries: [Entry]) -> String? {
        let k = key(name)
        let words = Set(k.split(separator: " "))
        guard !k.isEmpty, let e = entries.first(where: { $0.key == k }) ?? entries.first(where: { e in
            let w = Set(e.key.split(separator: " "))
            return w.isSuperset(of: words) || words.isSuperset(of: w)   // whole words: "egg" never matches "eggplant"
        }) else { return nil }
        var s = "last " + e.last.formatted(.currency(code: "USD"))
        if let c = e.cheapestStore { s += " · cheapest at \(c)" }
        return s
    }

    struct StorePick { let store: String; let cheapestFor: Int; let known: Int; let savings: Double }

    /// Which store is cheapest for this list, from what you've paid before (average per store per item).
    static func bestStore(for names: [String], in entries: [Entry]) -> StorePick? {
        var perStore: [String: (count: Int, savings: Double)] = [:]
        var known = 0
        for n in names {
            let k = key(n)
            guard !k.isEmpty, let e = entries.first(where: { $0.key == k }) else { continue }
            let avg = Dictionary(grouping: e.paid.filter { $0.store != "Unknown" }, by: \.store).mapValues { $0.map(\.price).reduce(0, +) / Double($0.count) }
            guard avg.count > 1, let best = avg.min(by: { $0.value < $1.value }) else { continue }
            known += 1
            let others = avg.values.filter { $0 != best.value }
            let saving = others.isEmpty ? 0 : others.reduce(0, +) / Double(others.count) - best.value
            perStore[best.key, default: (0, 0)].count += 1
            perStore[best.key, default: (0, 0)].savings += saving
        }
        guard known >= 2, let top = perStore.max(by: { $0.value.count == $1.value.count ? $0.value.savings < $1.value.savings : $0.value.count < $1.value.count })
        else { return nil }
        return StorePick(store: top.key, cheapestFor: top.value.count, known: known, savings: top.value.savings)
    }
}
