import Foundation
import SwiftData

/// Learns how fast you go through things and keeps the shopping list ahead of you.
@MainActor
enum ShoppingBrain {
    /// Store-walk order so the list reads like an aisle path.
    static let aisleOrder: [FoodCategory] = [.produce, .fruit, .bakery, .deli, .meat, .poultry, .seafood, .cheese, .dairy, .eggs,
                                             .grains, .canned, .condiments, .snacks, .beverages, .frozen, .other]

    static func key(_ name: String) -> String {
        name.lowercased().trimmingCharacters(in: .whitespaces)
            .replacing(/\b(organic|fresh|large|small|medium|lb|oz|pack|ct)\b/, with: "")
            .replacing(/\s+/, with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// Typical days between buying the same thing (needs 3+ purchases).
    static func paces(_ items: [PantryItem]) -> [String: (days: Double, name: String, category: FoodCategory, last: Date)] {
        var out: [String: (days: Double, name: String, category: FoodCategory, last: Date)] = [:]
        for (k, group) in Dictionary(grouping: items, by: { key($0.name) }) where group.count >= 3 && !k.isEmpty {
            let dates = group.map(\.purchaseDate).sorted()
            let gaps = zip(dates.dropFirst(), dates).map { $0.timeIntervalSince($1) / 86_400 }.filter { $0 >= 1 }
            guard gaps.count >= 2 else { continue }
            let avg = gaps.reduce(0, +) / Double(gaps.count)
            out[k] = (days: avg, name: group.last!.name, category: group.last!.category, last: dates.last!)
        }
        return out
    }

    /// Adds things you're about to run out of, plus empty/low spices. Safe to call often.
    static func refreshRunningLow(context: ModelContext) {
        guard let items = try? context.fetch(FetchDescriptor<PantryItem>()),
              let list = try? context.fetch(FetchDescriptor<ShoppingItem>()),
              let spices = try? context.fetch(FetchDescriptor<Spice>()) else { return }
        let onList = Set(list.filter { !$0.isChecked }.map { key($0.name) })
        let inStock = Set(items.filter { !$0.isUsedUp && ($0.daysLeft ?? 99) > 1 && !$0.isLeftover }.map { key($0.name) })

        for (k, p) in paces(items) where !onList.contains(k) && !inStock.contains(k) {
            let since = Date.now.timeIntervalSince(p.last) / 86_400
            if since >= p.days * 0.85 {
                context.insert(ShoppingItem(name: p.name, category: p.category, reason: "You usually rebuy every \(Int(p.days.rounded())) days"))
            }
        }
        // Things you finished recently with nothing left in stock (buy-again candidates).
        let recentlyFinished = items.filter { $0.isUsedUp && !$0.wasTossed && ($0.usedUpDate ?? .distantPast) > .now.addingTimeInterval(-3 * 86_400) }
        let staples: Set<FoodCategory> = [.eggs, .dairy, .bakery]
        for i in recentlyFinished where staples.contains(i.category) && !onList.contains(key(i.name)) && !inStock.contains(key(i.name)) {
            context.insert(ShoppingItem(name: i.name, category: i.category, reason: "Ran out"))
        }
        for s in spices where (s.level == .empty || s.level == .low) && !onList.contains(key(s.name)) {
            context.insert(ShoppingItem(name: s.name, category: .condiments, reason: s.level == .empty ? "Spice is empty" : "Spice is low"))
        }
    }

    /// Adds what a meal plan needs.
    static func add(needToBuy: [String], for dish: String, day: Date, context: ModelContext) {
        let list = (try? context.fetch(FetchDescriptor<ShoppingItem>())) ?? []
        let onList = Set(list.filter { !$0.isChecked }.map { key($0.name) })
        let dayName = day.formatted(.dateTime.weekday(.abbreviated))
        for n in needToBuy where !onList.contains(key(n)) {
            context.insert(ShoppingItem(name: n.capitalized, category: guessCategory(n), reason: "For \(dayName): \(dish)"))
        }
    }

    /// When groceries arrive (scan/Gmail), tick them off the list.
    static func checkOff(names: [String], context: ModelContext) {
        let keys = Set(names.map(key))
        for item in (try? context.fetch(FetchDescriptor<ShoppingItem>())) ?? [] where !item.isChecked {
            let k = key(item.name)
            if keys.contains(k) || keys.contains(where: { $0.contains(k) || k.contains($0) }) { item.isChecked = true }
        }
    }

    static func guessCategory(_ name: String) -> FoodCategory {
        let n = name.lowercased()
        let map: [(FoodCategory, [String])] = [
            (.seafood, ["shrimp", "salmon", "fish", "cod", "tuna", "scallop", "clam", "mussel", "crab", "lobster"]),
            (.poultry, ["chicken", "turkey", "duck"]),
            (.meat, ["beef", "steak", "pork", "lamb", "bacon", "sausage", "veal", "ground"]),
            (.cheese, ["cheese", "mozzarella", "parmesan", "brie", "cheddar", "gouda", "ricotta", "feta", "boursin"]),
            (.dairy, ["milk", "cream", "butter", "yogurt"]),
            (.eggs, ["egg"]),
            (.fruit, ["apple", "lemon", "lime", "orange", "berry", "banana", "grape", "peach", "mango", "avocado"]),
            (.produce, ["onion", "garlic", "tomato", "lettuce", "spinach", "pepper", "potato", "carrot", "herb", "basil", "parsley", "cilantro", "mushroom", "zucchini", "kale", "broccoli", "shallot", "ginger", "celery", "cucumber", "arugula", "scallion", "asparagus"]),
            (.bakery, ["bread", "bun", "roll", "baguette", "tortilla", "pita"]),
            (.grains, ["rice", "pasta", "flour", "oat", "quinoa", "noodle", "couscous", "farro"]),
            (.canned, ["can", "broth", "stock", "beans", "chickpea", "tomato paste"]),
            (.condiments, ["sauce", "vinegar", "mustard", "mayo", "honey", "oil", "ketchup", "salsa"]),
            (.frozen, ["frozen"]),
            (.beverages, ["wine", "juice", "soda", "water", "coffee", "tea", "beer"]),
        ]
        return map.first { $0.1.contains(where: n.contains) }?.0 ?? .other
    }
}
