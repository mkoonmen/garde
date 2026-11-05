import Foundation

/// Hard safety net for allergies. The AI is told about allergies in its prompt,
/// but small on-device models can slip — so every recipe is ALSO checked here
/// in plain code and rejected if any ingredient or step mentions an allergen.
enum AllergenGuard {
    /// Allergy words → the ingredient words that count as that allergen.
    static let families: [String: [String]] = [
        "shellfish": ["shrimp", "prawn", "crab", "lobster", "crawfish", "crayfish", "scallop", "clam", "mussel", "oyster", "langoustine", "shellfish"],
        "fish": ["fish", "salmon", "tuna", "cod", "halibut", "anchov", "sardine", "tilapia", "trout", "bass", "snapper", "swordfish", "mahi", "fish sauce", "worcestershire"],
        "peanut": ["peanut", "groundnut"],
        "tree nut": ["almond", "walnut", "pecan", "cashew", "pistachio", "hazelnut", "macadamia", "brazil nut", "pine nut", "praline", "marzipan", "nutella", "pesto"],
        "dairy": ["milk", "butter", "cream", "cheese", "yogurt", "yoghurt", "ghee", "whey", "casein", "mozzarella", "parmesan", "brie", "cheddar", "gouda", "ricotta", "boursin", "mascarpone"],
        "milk": ["milk", "butter", "cream", "cheese", "yogurt", "ghee", "whey", "casein"],
        "egg": ["egg", "mayonnaise", "mayo", "aioli", "meringue"],
        "gluten": ["wheat", "flour", "bread", "pasta", "barley", "rye", "couscous", "breadcrumb", "panko", "soy sauce", "seitan", "farro", "tortilla", "beer"],
        "wheat": ["wheat", "flour", "bread", "pasta", "couscous", "breadcrumb", "panko", "tortilla"],
        "soy": ["soy", "tofu", "edamame", "miso", "tempeh", "tamari"],
        "sesame": ["sesame", "tahini", "hummus"],
        "mustard": ["mustard"],
        "celery": ["celery", "celeriac"],
    ]

    /// Expands the user's allergy list into every word to look for.
    static func terms(for allergies: [String]) -> [String] {
        var out: Set<String> = []
        for raw in allergies {
            let a = raw.lowercased().trimmingCharacters(in: .whitespaces)
            guard !a.isEmpty else { continue }
            out.insert(a)
            // match "nuts" → "tree nut", "peanuts" → "peanut", "eggs" → "egg"
            let singular = a.hasSuffix("s") ? String(a.dropLast()) : a
            out.insert(singular)
            for (family, words) in families where family == a || family == singular || a.contains(family) {
                words.forEach { out.insert($0) }
            }
        }
        return Array(out)
    }

    /// Returns the allergen words found in the text (empty = safe).
    static func violations(in texts: [String], allergies: [String]) -> [String] {
        let haystack = texts.joined(separator: " ").lowercased()
        return terms(for: allergies).filter { term in
            // "eggplant" shouldn't trip "egg"; "butternut" shouldn't trip "butter"
            let exceptions = ["egg": ["eggplant"], "butter": ["butternut", "peanut butter"], "nut": ["butternut", "nutmeg", "coconut"]]
            var h = haystack
            for ex in exceptions[term] ?? [] { h = h.replacingOccurrences(of: ex, with: "") }
            return h.contains(term)
        }.sorted()
    }
}
