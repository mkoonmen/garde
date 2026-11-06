import Foundation
import SwiftData

/// Learns how fast you go through things and keeps the shopping list ahead of you.
enum ShoppingBrain {
    /// Store-walk order so the list reads like an aisle path.
    static let aisleOrder: [FoodCategory] = [.produce, .fruit, .bakery, .deli, .meat, .poultry, .seafood, .cheese, .dairy, .eggs,
                                             .grains, .canned, .condiments, .snacks, .beverages, .frozen, .other]

    static func key(_ name: String) -> String {
        name.lowercased().trimmingCharacters(in: .whitespaces)
            .replacing(/\b(organic|fresh|large|small|medium|lb|oz|pack|ct)\b/, with: "")
            .replacing(/\s+/, with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// Does this pantry item show up in a recipe's text? Matches on meaningful words, so
    /// "Boneless Skinless Chicken Thigh" matches "1 lb chicken thighs".
    static func appears(_ itemName: String, in text: String) -> Bool {
        let t = text.lowercased()
        let k = key(itemName)
        guard !k.isEmpty else { return false }
        if t.contains(k) { return true }
        let filler: Set<String> = ["boneless", "skinless", "organic", "whole", "fresh", "large", "small", "baby", "sliced", "shredded", "great", "value", "kirkland", "signature"]
        let words = k.split(separator: " ").map(String.init).filter { $0.count > 3 && !filler.contains($0) }
        guard !words.isEmpty else { return false }
        return words.allSatisfy { w in t.contains(w) || (w.hasSuffix("s") && t.contains(String(w.dropLast()))) }
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
    @MainActor
    static func refreshRunningLow(context: ModelContext) {
        guard let items = try? context.fetch(FetchDescriptor<PantryItem>()),
              let list = try? context.fetch(FetchDescriptor<ShoppingItem>()),
              let spices = try? context.fetch(FetchDescriptor<Spice>()) else { return }
        var onList = Set(list.filter { !$0.isChecked }.map { key($0.name) })
        let inStock = Set(items.filter { !$0.isUsedUp && ($0.daysLeft ?? 99) > 1 && !$0.isLeftover }.map { key($0.name) })

        for (k, p) in paces(items) where !onList.contains(k) && !inStock.contains(k) {
            let since = Date.now.timeIntervalSince(p.last) / 86_400
            if since >= p.days * 0.85 {
                context.insert(ShoppingItem(name: p.name, category: p.category, reason: "You usually rebuy every \(Int(p.days.rounded())) days"))
                onList.insert(k)
            }
        }
        // Things you finished recently with nothing left in stock (buy-again candidates).
        let recentlyFinished = items.filter { $0.isUsedUp && !$0.wasTossed && ($0.usedUpDate ?? .distantPast) > .now.addingTimeInterval(-3 * 86_400) }
        let staples: Set<FoodCategory> = [.eggs, .dairy, .bakery]
        for i in recentlyFinished where staples.contains(i.category) && !onList.contains(key(i.name)) && !inStock.contains(key(i.name)) {
            context.insert(ShoppingItem(name: i.name, category: i.category, reason: "Ran out"))
            onList.insert(key(i.name))
        }
        for s in spices where (s.level == .empty || s.level == .low) && !onList.contains(key(s.name)) {
            context.insert(ShoppingItem(name: s.name, category: .condiments, reason: s.level == .empty ? "Spice is empty" : "Spice is low"))
            onList.insert(key(s.name))
        }
    }

    /// Adds what a meal plan needs.
    @MainActor
    static func add(needToBuy: [String], for dish: String, day: Date, context: ModelContext) {
        let list = (try? context.fetch(FetchDescriptor<ShoppingItem>())) ?? []
        var onList = Set(list.filter { !$0.isChecked }.map { key($0.name) })
        let dayName = day.formatted(.dateTime.weekday(.abbreviated))
        for n in needToBuy where !onList.contains(key(n)) {
            context.insert(ShoppingItem(name: n.capitalized, category: guessCategory(n), reason: "For \(dayName): \(dish)"))
            onList.insert(key(n))
        }
    }

    /// When groceries arrive (scan/Gmail), tick them off the list.
    @MainActor
    static func checkOff(names: [String], context: ModelContext) {
        // Ignore blanks and placeholders; match whole words so "egg" never ticks off "Eggplant".
        let keys = Set(names.map(key).filter { $0.count >= 3 && !$0.hasPrefix("looking up") })
        guard !keys.isEmpty else { return }
        for item in (try? context.fetch(FetchDescriptor<ShoppingItem>())) ?? [] where !item.isChecked {
            let k = key(item.name)
            guard k.count >= 3 else { continue }
            // Only when every word of the list item is in what was bought: "Butter" bought never ticks off "Peanut butter".
            if keys.contains(k) || keys.contains(where: { sameItem(list: k, bought: $0) }) { item.isChecked = true }
        }
    }

    /// Whole-word match either way: "eggs" ~ "large brown eggs", "milk" ~ "whole milk"; never "egg" ~ "eggplant".
    static func words(_ s: String) -> Set<String> {
        Set(s.lowercased().split { !$0.isLetter }.map { w in let w = String(w); return w.count > 3 && w.hasSuffix("s") && !w.hasSuffix("ss") ? String(w.dropLast()) : w })
    }

    /// Words that turn one food into a different one: "peanut butter" isn't butter, "almond milk" isn't milk.
    static let modifiers: Set<String> = ["peanut", "almond", "oat", "soy", "coconut", "cashew", "apple", "cocoa", "egg", "rice", "corn",
                                         "pumpkin", "sunflower", "nut", "chocolate", "ice", "cream", "sour", "butter", "cheese", "chicken", "beef"]

    /// Is something bought ("Large Brown Eggs") the list item ("eggs")? Every list word must be there, the last word (the food)
    /// must match, and no extra word may turn it into another food.
    static func sameItem(list: String, bought: String) -> Bool {
        let l = key(list).split { !$0.isLetter }.map { words(String($0)).first ?? String($0) }
        let sizes: Set<String> = ["gallon", "gal", "qt", "quart", "pint", "lb", "oz", "ct", "pack", "pk", "dozen", "each", "bag", "box",
                                  "bottle", "jar", "can", "loaf", "carton", "value", "family", "size", "count"]
        let b = key(bought).split { !$0.isLetter }.map { words(String($0)).first ?? String($0) }.filter { !sizes.contains($0) }
        guard let lHead = l.last, let bHead = b.last, lHead == bHead, Set(l).isSubset(of: Set(b)) else { return false }
        let extra = Set(b).subtracting(l)
        return extra.isDisjoint(with: modifiers)
    }

    static func sameFood(_ a: String, _ b: String) -> Bool {
        let x = words(a), y = words(b)
        guard !x.isEmpty, !y.isEmpty else { return false }
        return x.isSubset(of: y) || y.isSubset(of: x)
    }

    static func guessCategory(_ name: String) -> FoodCategory {
        let n = name.lowercased()
        let map: [(FoodCategory, [String])] = [
            // packaged look-alikes first ("chicken broth" is canned, not poultry)
            (.canned, ["broth", "stock", "canned", "beans", "chickpea", "tomato paste", "crushed tomato"]),
            (.condiments, ["sauce", "vinegar", "mustard", "mayo", "dressing", "peanut butter", "ketchup", "salsa", "honey"]),
            (.frozen, ["frozen", "ice cream"]),
            (.beverages, ["juice", "wine", "soda", "seltzer", "coffee", "tea", "beer"]),
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
        return map.first { $0.1.contains(where: { n.contains($0) }) }?.0 ?? .other
    }
}
