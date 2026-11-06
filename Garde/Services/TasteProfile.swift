import Foundation

/// Offline summary of what you actually eat: proteins and styles from home cooking (ratings) and takeout.
enum TasteProfile {
    static let proteins: [(String, [String])] = [
        ("Chicken", ["chicken"]), ("Beef", ["beef", "steak", "ribeye", "burger", "brisket", "short rib"]), ("Pork", ["pork", "bacon", "ham", "carnitas", "sausage"]),
        ("Seafood", ["salmon", "shrimp", "fish", "cod", "tuna", "scallop", "crab", "lobster", "bass", "halibut", "clam", "mussel"]),
        ("Turkey", ["turkey"]), ("Lamb", ["lamb"]), ("Vegetarian", ["tofu", "veggie", "vegetarian", "chickpea", "lentil", "bean"]), ("Eggs", ["egg", "omelet", "frittata"]),
    ]
    static let styles: [(String, [String])] = [
        ("Italian", ["pasta", "risotto", "parm", "piccata", "marsala", "pizza", "gnocchi", "carbonara", "bolognese"]),
        ("Mexican", ["taco", "burrito", "enchilada", "quesadilla", "fajita", "carnitas", "salsa"]),
        ("Asian", ["stir fry", "stir-fry", "teriyaki", "pad", "curry", "ramen", "fried rice", "sushi", "bao", "lo mein", "bibimbap", "pho"]),
        ("American", ["burger", "bbq", "wings", "mac and cheese", "fries", "sandwich", "meatloaf"]),
        ("Mediterranean", ["greek", "gyro", "shawarma", "hummus", "falafel", "kebab"]),
        ("Soups & stews", ["soup", "stew", "chili", "chowder"]),
        ("Salads & bowls", ["salad", "bowl"]),
    ]

    /// Counts by category, most first. Home dishes rated 4+ count double.
    static func rank(_ table: [(String, [String])], home: [CookLog], takeout: [TakeoutOrder]) -> [(String, Int)] {
        var count: [String: Int] = [:]
        func add(_ text: String, _ weight: Int) {
            let t = text.lowercased()
            for (name, words) in table where words.contains(where: { t.contains($0) }) { count[name, default: 0] += weight }
        }
        for l in home where !l.neverAgain { add(l.title, l.rating >= 4 ? 2 : 1) }
        for o in takeout { o.dishes.forEach { add($0, 1) }; add(o.cuisine, 1) }
        return count.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    static func average(_ logs: [CookLog]) -> Double? {
        let rated = logs.filter { $0.rating > 0 }
        return rated.isEmpty ? nil : Double(rated.map(\.rating).reduce(0, +)) / Double(rated.count)
    }
}
