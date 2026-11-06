import Foundation

/// Scales ingredient lines ("1 1/2 cups flour" × 2 → "3 cups flour"). Works offline, no AI.
enum RecipeScaler {
    private static let unicode: [Character: Double] = ["½": 0.5, "⅓": 1.0 / 3, "⅔": 2.0 / 3, "¼": 0.25, "¾": 0.75, "⅛": 0.125, "⅜": 0.375, "⅝": 0.625, "⅞": 0.875]

    /// Leading amount of a line and where it ends, e.g. "1 1/2 cups" → (1.5, index after "1 1/2").
    static func leadingAmount(_ line: String) -> (value: Double, end: String.Index)? {
        var i = line.startIndex
        var total = 0.0, found = false
        func skipSpaces() { while i < line.endIndex, line[i] == " " { i = line.index(after: i) } }
        skipSpaces()
        for _ in 0..<2 {   // whole number then optional fraction ("1 1/2", "1½")
            let start = i
            if i < line.endIndex, let u = unicode[line[i]] { total += u; found = true; i = line.index(after: i); skipSpaces(); continue }
            while i < line.endIndex, line[i].isNumber || line[i] == "." || line[i] == "/" { i = line.index(after: i) }
            let token = String(line[start..<i])
            if token.isEmpty { break }
            if token.contains("/") {
                let p = token.split(separator: "/")
                guard p.count == 2, let a = Double(p[0]), let b = Double(p[1]), b != 0 else { return found ? (total, start) : nil }
                total += a / b
            } else if let v = Double(token) { total += v } else { return found ? (total, start) : nil }
            found = true
            if i < line.endIndex, let u = unicode[line[i]] { total += u; i = line.index(after: i) }
            let afterNumber = i
            skipSpaces()
            // Only keep going if the next token is a fraction ("1 1/2"), not a size ("1 14-oz can").
            let rest = line[i...]
            let isFraction = rest.first.map { unicode[$0] != nil } == true || rest.prefix(while: { $0.isNumber || $0 == "/" }).contains("/")
            if !isFraction { i = afterNumber; break }
        }
        return found && total > 0 ? (total, i) : nil
    }

    static func format(_ v: Double) -> String {
        let whole = Int(v.rounded(.down)), frac = v - Double(whole)
        let options: [(Double, String)] = [(0, ""), (0.125, "1/8"), (0.25, "1/4"), (1.0 / 3, "1/3"), (0.5, "1/2"), (2.0 / 3, "2/3"), (0.75, "3/4"), (1, "")]
        let best = options.min { abs($0.0 - frac) < abs($1.0 - frac) }!
        if v >= 10 { return String(Int(v.rounded())) }
        if best.0 == 1 { return String(whole + 1) }
        if best.1.isEmpty { return whole == 0 ? "1/8" : String(whole) }
        return whole == 0 ? best.1 : "\(whole) \(best.1)"
    }

    static func scale(_ line: String, by factor: Double) -> String {
        guard factor != 1, let (v, end) = leadingAmount(line) else { return line }
        var rest = String(line[end...])
        // Ranges: "2-3 cloves", "2 to 3 cloves", "1–2 tbsp" scale both ends.
        for sep in ["-", "–", " to ", "to "] where rest.hasPrefix(sep) {
            let after = String(rest.dropFirst(sep.count))
            guard let (v2, end2) = leadingAmount(after) else { return line }
            let tail = after[end2...]
            if sep == "-", v2 < 1, after.prefix(while: { $0 != " " }).contains("/") {   // "1-1/2 cups" is one and a half
                return format((v + v2) * factor) + (tail.first == " " || tail.isEmpty ? "" : " ") + tail
            }
            let joiner = sep.trimmingCharacters(in: .whitespaces) == "to" ? " to " : "-"
            return format(v * factor) + joiner + format(v2 * factor) + (tail.first == " " || tail.isEmpty ? "" : " ") + tail
        }
        if rest.hasPrefix("/") { return line }   // something we didn't understand
        if rest.first == "-" { rest.removeFirst() }
        return format(v * factor) + (rest.first == " " || rest.isEmpty ? "" : " ") + rest
    }

    /// The food in an ingredient line: "1 1/2 cups heavy cream, warmed" → "heavy cream".
    static func foodName(_ line: String) -> String {
        var rest = line
        if let (_, end) = leadingAmount(line) { rest = String(line[end...]) }
        rest = rest.components(separatedBy: CharacterSet(charactersIn: ",(")).first ?? rest
        let units: Set<String> = ["cup", "cups", "tbsp", "tsp", "tablespoon", "tablespoons", "teaspoon", "teaspoons", "oz", "ounce", "ounces",
                                  "lb", "lbs", "pound", "pounds", "g", "kg", "ml", "l", "clove", "cloves", "can", "cans", "pinch", "dash",
                                  "bunch", "sprig", "sprigs", "slice", "slices", "piece", "pieces", "large", "medium", "small", "of", "to", "taste"]
        let words = rest.split(separator: " ").map(String.init).filter { !units.contains($0.lowercased()) && !$0.contains("-oz") }
        return words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    /// Ingredient lines with nothing matching in the kitchen (salt, pepper, oil and water assumed).
    static func missing(_ lines: [String], have items: [PantryItem]) -> [String] {
        KitchenStock.plan(lines, items: items).filter { !$0.covered }.map(\.shoppingLine)
    }
}
