import Foundation
import FoundationModels
import SwiftData

/// Reads restaurant delivery receipts (DoorDash, Uber Eats, Grubhub, Seamless, Caviar, Postmates)
/// and learns what you like to order, so the chef can suggest making it at home.
@MainActor
enum Takeout {
    /// Delivery service if this email is a restaurant order (grocery orders through these apps are skipped here
    /// and handled as groceries instead).
    /// Whole-word match so "Rinaldi's Pizza" isn't mistaken for ALDI.
    nonisolated static func isGrocery(subject: String) -> Bool {
        let s = " " + subject.lowercased().replacingOccurrences(of: "[^a-z0-9&]+", with: " ", options: .regularExpression) + " "
        return groceryWords.contains { s.contains(" " + $0.replacingOccurrences(of: "-", with: " ") + " ") }
    }

    nonisolated static let groceryWords = ["dashmart", "grocery", "groceries", "safeway", "costco", "aldi", "cvs", "walgreens", "7-eleven", "convenience", "wegmans", "stop & shop", "sprouts"]

    nonisolated static func service(from: String, subject: String) -> String? {
        let f = " " + from.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression) + " "
        if isGrocery(subject: subject) { return nil }
        let s = subject.lowercased()
        if f.contains("doordash") { return "DoorDash" }
        if f.contains("uber") && (s.contains("eats") || s.contains("order") || s.contains("receipt")) && !s.contains("trip") && !s.contains("ride") { return "Uber Eats" }
        if f.contains("grubhub") { return "Grubhub" }
        if f.contains("seamless") { return "Seamless" }
        if f.contains("caviar") { return "Caviar" }
        if f.contains("postmates") { return "Postmates" }
        let chains: [(String, String)] = [("mcdonald", "McDonald's"), ("mcdonalds", "McDonald's"), ("wendy", "Wendy's"), ("wendys", "Wendy's"),
            ("chipotle", "Chipotle"), ("starbucks", "Starbucks"), ("dunkin", "Dunkin'"), ("chick fil a", "Chick-fil-A"), ("chickfila", "Chick-fil-A"),
            ("burger king", "Burger King"), ("taco bell", "Taco Bell"), ("domino", "Domino's"), ("dominos", "Domino's"), ("papa john", "Papa John's"),
            ("papajohns", "Papa John's"), ("pizza hut", "Pizza Hut"), ("pizzahut", "Pizza Hut"), ("panera", "Panera"), ("sweetgreen", "Sweetgreen"),
            ("shake shack", "Shake Shack"), ("shakeshack", "Shake Shack"), ("five guys", "Five Guys"), ("subway", "Subway"), ("popeyes", "Popeyes"),
            ("kfc", "KFC"), ("cava", "CAVA"), ("panda express", "Panda Express"), ("jersey mike", "Jersey Mike's"), ("wingstop", "Wingstop"),
            ("arbys", "Arby's"), ("dairy queen", "Dairy Queen"), ("toasttab", "Toast"), ("toast", "Toast")]
        // Whole words of the sender only, so "Supersonic" or "Cavalier" don't count.
        if let c = chains.first(where: { f.contains(" " + $0.0 + " ") || f.contains(" " + $0.0 + "s ") }) { return c.1 }
        return nil
    }

    @Generable
    struct Parsed {
        @Guide(description: "Restaurant name")
        var restaurant: String
        @Guide(description: "Cuisine in one or two words, e.g. 'Thai', 'Italian', 'Burgers', 'Sushi', 'Mexican'")
        var cuisine: String
        @Guide(description: "Each food or drink item ordered, cleaned up, without prices, quantities or add-on fees. Skip fees, tips, taxes, utensils.")
        var dishes: [String]
        @Guide(description: "Order total in dollars, or 0")
        var total: Double
    }

    static func parse(subject: String, from: String, body: String, date: Date, service: String) async -> TakeoutOrder? {
        let focus = EmailReceipt.focus(body)
        let text = "From: \(from)\nSubject: \(subject)\n\n" + String(focus.text.prefix(3000))
        guard SystemLanguageModel.default.availability == .available || ChefEngine.shared.usingLocal else { return nil }
        let session = ChefEngine.shared.session(instructions: "You read food delivery receipts and list the restaurant and the dishes ordered. Never invent dishes.")
        guard let p = try? await session.reply(to: text, generating: Parsed.self, limit: 30) else { return nil }
        let dishes = p.dishes.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { d in d.count > 1 && !["fee", "tip", "tax", "utensil", "napkin", "service"].contains(where: { d.lowercased().contains($0) }) }
        guard !p.restaurant.isEmpty, !dishes.isEmpty else { return nil }
        return TakeoutOrder(restaurant: p.restaurant, cuisine: p.cuisine, date: date, dishes: dishes,
                            total: p.total > 0 ? p.total : focus.total, service: service)
    }

    /// Dishes and cuisines ranked by how often you order them.
    static func favorites(_ orders: [TakeoutOrder]) -> (dishes: [(String, Int)], cuisines: [(String, Int)], restaurants: [(String, Int)]) {
        func rank(_ xs: [String]) -> [(String, Int)] {
            var count: [String: (String, Int)] = [:]
            for x in xs where !x.isEmpty {
                let k = x.lowercased()
                count[k] = (count[k]?.0 ?? x, (count[k]?.1 ?? 0) + 1)
            }
            return count.values.sorted { $0.1 > $1.1 }
        }
        return (rank(orders.flatMap(\.dishes)), rank(orders.map(\.cuisine)), rank(orders.map(\.restaurant)))
    }

    /// One line for the chef's instructions so suggestions lean toward what you actually order.
    static func tasteHint(_ orders: [TakeoutOrder]) -> String {
        guard !orders.isEmpty else { return "" }
        let f = favorites(orders)
        let dishes = f.dishes.prefix(8).map(\.0).joined(separator: ", ")
        let cuisines = f.cuisines.prefix(4).map(\.0).joined(separator: ", ")
        return "Takeout they order most: \(dishes). Favorite cuisines: \(cuisines). Homemade versions of these are welcome."
    }
}
