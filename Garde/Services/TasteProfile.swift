import Foundation

/// Offline summary of what you actually eat: proteins and styles from home cooking (ratings) and takeout.
enum TasteProfile {
    static let proteins: [(String, [String])] = [
        ("Chicken", ["chicken"]), ("Beef", ["beef", "steak", "ribeye", "burger", "brisket", "short rib"]), ("Pork", ["pork", "bacon", "ham", "carnitas", "sausage"]),
        ("Seafood", ["salmon", "shrimp", "fish", "cod", "tuna", "scallop", "crab", "lobster", "bass", "halibut", "clam", "mussel"]),
        ("Turkey", ["turkey"]), ("Lamb", ["lamb"]), ("Vegetarian", ["tofu", "veggie", "vegetarian", "chickpea", "lentil", "black bean"]), ("Eggs", ["egg", "omelet", "frittata"]),
    ]
    static let styles: [(String, [String])] = [
        ("Italian", ["pasta", "risotto", "parm", "piccata", "marsala", "pizza", "gnocchi", "carbonara", "bolognese"]),
        ("Mexican", ["taco", "burrito", "enchilada", "quesadilla", "fajita", "carnitas", "salsa"]),
        ("Asian", ["stir fry", "stir-fry", "teriyaki", "pad thai", "pad see ew", "curry", "ramen", "fried rice", "sushi", "bao", "lo mein", "bibimbap", "pho"]),
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
            let tokens = Set(t.split { !$0.isLetter }.map(String.init))
            // Multi-word keys match as phrases; single words must be whole words ("eggplant" isn't eggs, "hamburger" isn't ham).
            func hit(_ k: String) -> Bool { k.contains(" ") || k.contains("-") ? t.contains(k) : tokens.contains(k) || tokens.contains(k + "s") }
            for (name, words) in table where words.contains(where: hit) { count[name, default: 0] += weight }
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

/// A simple monthly grade for how the kitchen is going: waste, cooking at home, and budget.
enum ReportCard {
    struct Card { let grade: String; let points: Int; let notes: [String] }

    static func make(items: [PantryItem], logs: [CookLog], takeout: [TakeoutOrder], spent: Double, budget: Double, now: Date = .now) -> Card? {
        let start = Calendar.current.dateInterval(of: .month, for: now)?.start ?? now
        let finished = items.filter { $0.isUsedUp && ($0.usedUpDate ?? .distantPast) >= start }
        let cooked = logs.filter { $0.date >= start }.count
        let ordered = takeout.filter { $0.date >= start }.count
        guard finished.count + cooked + ordered >= 3 else { return nil }
        var points = 0, notes: [String] = []
        // Waste: up to 40 points
        let tossed = finished.filter(\.wasTossed).count
        let wasteRate = finished.isEmpty ? 0 : Double(tossed) / Double(finished.count)
        points += Int((40 * (1 - min(wasteRate / 0.3, 1))).rounded())
        notes.append(tossed == 0 ? "Nothing thrown away" : "\(tossed) of \(finished.count) items tossed (\(Int((wasteRate * 100).rounded()))%)")
        // Home cooking: up to 35 points
        let homeShare = cooked + ordered == 0 ? 0.5 : Double(cooked) / Double(cooked + ordered)
        points += Int((35 * min(homeShare / 0.75, 1)).rounded())
        notes.append("\(cooked) cooked at home, \(ordered) takeout")
        // Budget: 25 points (full marks with no budget set but some spending tracked)
        if budget > 0 {
            let day = Double(Calendar.current.component(.day, from: now))
            let days = Double(Calendar.current.range(of: .day, in: .month, for: now)?.count ?? 30)
            let pace = day < 7 ? spent + budget / days * (days - day) : spent / day * days
            points += pace <= budget ? 25 : max(0, 25 - Int(((pace - budget) / budget * 100).rounded()))
            notes.append(pace <= budget ? "On pace for your budget" : "On pace to go over budget")
        } else { points += 20 }
        let grade = points >= 90 ? "A" : points >= 80 ? "B" : points >= 70 ? "C" : points >= 60 ? "D" : "F"
        return Card(grade: grade, points: points, notes: notes)
    }
}
