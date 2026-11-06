import Foundation

struct FoodMeasure: Codable, Equatable {
    enum Dimension: String, Codable { case volume, mass, count }
    var value: Double
    var dimension: Dimension
    var unit: String { dimension == .volume ? "ml" : dimension == .mass ? "g" : "each" }
    var label: String { "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)" }

    static let units: [(String, Double, Dimension)] = [
        ("fluid ounces", 29.5735, .volume), ("fl oz", 29.5735, .volume),
        ("tablespoons", 14.7868, .volume), ("tablespoon", 14.7868, .volume), ("tbsp", 14.7868, .volume),
        ("teaspoons", 4.92892, .volume), ("teaspoon", 4.92892, .volume), ("tsp", 4.92892, .volume),
        ("gallons", 3785.41, .volume), ("gallon", 3785.41, .volume), ("gal", 3785.41, .volume),
        ("quarts", 946.353, .volume), ("quart", 946.353, .volume), ("qt", 946.353, .volume),
        ("pints", 473.176, .volume), ("pint", 473.176, .volume), ("cups", 236.588, .volume), ("cup", 236.588, .volume),
        ("milliliters", 1, .volume), ("ml", 1, .volume), ("liters", 1000, .volume), ("liter", 1000, .volume), ("l", 1000, .volume),
        ("kilograms", 1000, .mass), ("kg", 1000, .mass), ("grams", 1, .mass), ("gram", 1, .mass), ("g", 1, .mass),
        ("pounds", 453.592, .mass), ("pound", 453.592, .mass), ("lbs", 453.592, .mass), ("lb", 453.592, .mass),
        ("ounces", 28.3495, .mass), ("ounce", 28.3495, .mass), ("oz", 28.3495, .mass),
        ("each", 1, .count), ("eggs", 1, .count), ("egg", 1, .count), ("cloves", 1, .count), ("clove", 1, .count)
    ]

    static func amount(_ number: Double, unit: String) -> FoodMeasure? {
        guard number.isFinite, number >= 0,
              let entry = units.first(where: { $0.0 == unit.lowercased().trimmingCharacters(in: .whitespaces) }) else { return nil }
        return FoodMeasure(value: number * entry.1, dimension: entry.2)
    }

    static func parse(_ text: String) -> FoodMeasure? {
        var text = text.lowercased()
        for (symbol, number) in [("½", " 1/2"), ("¼", " 1/4"), ("¾", " 3/4"), ("⅓", " 1/3"), ("⅔", " 2/3")] {
            text = text.replacingOccurrences(of: symbol, with: number)
        }
        guard let regex = try? NSRegularExpression(pattern: #"^\s*(\d+(?:\.\d+)?(?:/\d+)?)(?:\s+(\d+/\d+))?\s*[- ]*"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let numberRange = Range(match.range(at: 1), in: text), let allRange = Range(match.range, in: text) else { return nil }
        func number(_ text: Substring) -> Double {
            let parts = text.split(separator: "/").compactMap { Double($0) }
            if parts.count == 2 { return parts[1] > 0 ? parts[0] / parts[1] : 0 }
            return parts.first ?? 0
        }
        var value = number(text[numberRange])
        if let fraction = Range(match.range(at: 2), in: text) { value += number(text[fraction]) }
        let tail = String(text[allRange.upperBound...])
        for (unit, factor, dimension) in units {
            if tail == unit || tail.hasPrefix(unit + " ") || tail.hasPrefix(unit + ".") {
                return FoodMeasure(value: value * factor, dimension: dimension)
            }
        }
        // Bare counts are useful for whole foods. An unrecognized unit stays unknown.
        let first = tail.split(separator: " ").map(String.init).filter { !["large", "medium", "small"].contains($0) }.first ?? ""
        if ["egg", "eggs", "onion", "onions", "lemon", "lemons", "lime", "limes", "carrot", "carrots", "potato", "potatoes"].contains(first) {
            return FoodMeasure(value: value, dimension: .count)
        }
        return nil
    }

    static func package(in name: String) -> FoodMeasure? {
        guard let regex = try? NSRegularExpression(pattern: #"\b\d+(?:\.\d+)?\s*(?:fl\s*oz|gal(?:lon)?|qt|pint|ml|kg|lb|oz|g|l)\b"#, options: .caseInsensitive),
              let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let range = Range(match.range, in: name) else { return nil }
        return parse(String(name[range]))
    }
}

extension PantryItem {
    var ingredientName: String { ingredientOverride.isEmpty ? FoodIdentity.ingredient(name) : ingredientOverride }
    var productKey: String { FoodIdentity.productKey(name, barcode: barcode) }
    var originalAmount: FoodMeasure? {
        if packageAmount > 0, let measure = FoodMeasure.amount(packageAmount, unit: packageUnit) {
            return FoodMeasure(value: measure.value * quantity, dimension: measure.dimension)
        }
        if unit == "each" || unit == "pack" || unit == "bottle" || unit == "jar" || unit == "carton" {
            if let measure = FoodMeasure.package(in: name) {
                return FoodMeasure(value: measure.value * quantity, dimension: measure.dimension)
            }
        }
        return FoodMeasure.amount(quantity, unit: unit)
    }
    var availableAmount: FoodMeasure? {
        guard var amount = originalAmount else { return nil }
        amount.value = isUsedUp ? 0 : max(0, remainingAmount ?? (amount.value * remainingFraction))
        return amount
    }
    var availableLabel: String {
        if let amount = availableAmount { return amount.label + " left" }
        return "About \(Int(remainingFraction * 100))% left"
    }
}
