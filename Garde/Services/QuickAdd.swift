import Foundation

/// Turns "eggs, 2 lb chicken thighs, a gallon of milk and spinach" into kitchen items, offline.
enum QuickAdd {
    struct Line: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var quantity: Double
        var unit: String
        var category: FoodCategory
        var location: StorageLocation
        var days: Int
    }

    static let units: [String: String] = [
        "lb": "lb", "lbs": "lb", "pound": "lb", "pounds": "lb", "oz": "oz", "ounce": "oz", "ounces": "oz",
        "gallon": "gal", "gallons": "gal", "gal": "gal", "quart": "qt", "quarts": "qt", "qt": "qt",
        "dozen": "dozen", "bunch": "bunch", "bunches": "bunch", "bag": "bag", "bags": "bag", "box": "box", "boxes": "box",
        "can": "can", "cans": "can", "jar": "jar", "jars": "jar", "pack": "pack", "packs": "pack", "bottle": "bottle", "bottles": "bottle",
        "loaf": "loaf", "loaves": "loaf", "carton": "carton", "cartons": "carton",
    ]
    static let numberWords: [String: Double] = ["a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "half": 0.5, "a couple": 2, "couple": 2]

    static func parse(_ text: String) -> [Line] {
        // Keep dish names whole ("mac and cheese", "salt & pepper chips"): only split on "and" between list items.
        var t = text.replacingOccurrences(of: "\n", with: ",")
        for keep in ["mac and cheese", "salt and pepper", "salt & pepper", "half and half", "half & half", "peanut butter and jelly", "rock and roll"] {
            t = t.replacingOccurrences(of: keep, with: keep.replacingOccurrences(of: " and ", with: "_and_").replacingOccurrences(of: " & ", with: "_amp_"), options: .caseInsensitive)
        }
        let parts = t
            .replacingOccurrences(of: #"\s+(and|plus|&)\s+"#, with: ",", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "_and_", with: " and ").replacingOccurrences(of: "_amp_", with: " & ")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
            .filter { !$0.isEmpty }
        return parts.compactMap(line)
    }

    static func line(_ input: String) -> Line? {
        var raw = input
        for (phrase, n) in [("half a dozen", "6"), ("a couple of", "2"), ("a couple", "2"), ("a few", "3")] where raw.lowercased().hasPrefix(phrase) {
            raw = n + raw.dropFirst(phrase.count)
        }
        var words = raw.split(separator: " ").map(String.init)
        var qty = 1.0, unit = "each"
        if let (v, end) = RecipeScaler.leadingAmount(raw) {
            qty = v
            words = String(raw[end...]).split(separator: " ").map(String.init)
        } else if let first = words.first?.lowercased(), let n = numberWords[first],
                  !(words.count > 1 && ["and", "&"].contains(words[1].lowercased())) {   // "half and half" is a food, not ½ of one
            qty = n; words.removeFirst()
        }
        if let u = words.first.flatMap({ units[$0.lowercased()] }) { unit = u; words.removeFirst() }
        if words.first?.lowercased() == "of" { words.removeFirst() }
        if unit == "dozen" { qty *= 12; unit = "each" }
        let name = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard name.count > 1 else { return nil }
        let pretty = name.prefix(1).uppercased() + name.dropFirst()
        let cat = ShoppingBrain.guessCategory(pretty)
        let loc = ShelfLife.defaultLocation(for: cat, name: pretty)
        return Line(name: pretty, quantity: qty, unit: unit, category: cat, location: loc,
                    days: ShelfLife.days(name: pretty, category: cat, location: loc))
    }
}
