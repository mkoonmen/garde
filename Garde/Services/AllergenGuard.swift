import Foundation

/// Hard safety net for allergies. The AI is told about allergies in its prompt,
/// but small on-device models can slip — so every recipe is ALSO checked here
/// in plain code and rejected if any ingredient or step mentions an allergen.
/// Errs on the side of caution: a false alarm (e.g. "crabapple") is acceptable, a miss is not.
enum AllergenGuard {
    /// Allergy words → the ingredient words that count as that allergen.
    static let families: [String: [String]] = [
        "shellfish": ["shrimp", "prawn", "crab", "lobster", "crawfish", "crayfish", "scallop", "clam", "mussel", "oyster",
                      "langoustine", "shellfish", "calamari", "squid", "octopus", "conch", "scampi", "cockle", "whelk"],
        "fish": ["fish", "salmon", "tuna", "cod", "halibut", "anchov", "sardine", "tilapia", "trout", "bass", "snapper", "swordfish",
                 "mahi", "branzino", "haddock", "flounder", "sole", "mackerel", "grouper", "pollock", "caviar", "roe", "bonito",
                 "dashi", "worcestershire", "caesar", "lox"],
        "peanut": ["peanut", "groundnut", "satay"],
        "tree nut": ["almond", "walnut", "pecan", "cashew", "pistachio", "hazelnut", "macadamia", "brazil nut", "pine nut",
                     "praline", "marzipan", "nutella", "pesto", "frangipane", "gianduja", "nut butter", "amaretto"],
        "dairy": ["milk", "butter", "cream", "creme", "crème", "cheese", "yogurt", "yoghurt", "ghee", "whey", "casein", "mozzarella",
                  "parmesan", "parmigiano", "pecorino", "brie", "cheddar", "gouda", "ricotta", "boursin", "mascarpone", "burrata",
                  "feta", "stracciatella", "half-and-half", "custard", "queso", "paneer", "kefir", "alfredo"],
        "egg": ["egg", "mayonnaise", "mayo", "aioli", "meringue", "custard", "hollandaise", "frittata", "quiche", "carbonara", "brioche"],
        "gluten": ["wheat", "flour", "bread", "pasta", "barley", "rye", "couscous", "breadcrumb", "panko", "soy sauce", "seitan",
                   "farro", "tortilla", "beer", "noodle", "ramen", "udon", "orzo", "gnocchi", "dumpling", "crouton", "pita", "naan",
                   "bun", "cracker", "roux", "biscuit", "pizza", "pastry", "phyllo", "spaghetti", "linguine", "penne", "fettuccine",
                   "lasagna", "ravioli", "tortellini", "bulgur", "semolina", "brioche"],
        "soy": ["soy", "tofu", "edamame", "miso", "tempeh", "tamari"],
        "sesame": ["sesame", "tahini", "hummus", "za'atar", "furikake"],
        "mustard": ["mustard"],
        "celery": ["celery", "celeriac"],
    ]

    /// Short names people type → families.
    static let aliases: [String: [String]] = [
        "milk": ["dairy"], "lactose": ["dairy"], "cheese": ["dairy"],
        "eggs": ["egg"],
        "nut": ["tree nut", "peanut"], "nuts": ["tree nut", "peanut"], "tree nuts": ["tree nut"],
        "peanuts": ["peanut"],
        "seafood": ["shellfish", "fish"], "crustacean": ["shellfish"], "crustaceans": ["shellfish"], "mollusk": ["shellfish"],
        "wheat": ["gluten"], "celiac": ["gluten"], "coeliac": ["gluten"],
        "soya": ["soy"],
    ]

    /// Expands the user's allergy list into every word to look for.
    static func terms(for allergies: [String]) -> [String] {
        var out: Set<String> = []
        for raw in allergies {
            let a = raw.lowercased().trimmingCharacters(in: .whitespaces)
            guard !a.isEmpty else { continue }
            let singular = a.hasSuffix("s") ? String(a.dropLast()) : a
            out.insert(a)
            out.insert(singular)
            var famNames: Set<String> = []
            if families[a] != nil { famNames.insert(a) }
            if families[singular] != nil { famNames.insert(singular) }
            aliases[a].map { famNames.formUnion($0) }
            aliases[singular].map { famNames.formUnion($0) }
            for f in famNames { families[f]?.forEach { out.insert($0) } }
        }
        return Array(out)
    }

    /// Words that contain an allergen word but aren't that allergen.
    static let harmless: [String: [String]] = [
        "egg": ["eggplant", "veggie", "nutmeg"],
        "butter": ["butternut", "peanut butter", "butter bean", "butterhead", "butterfly"],
        "nut": ["butternut", "nutmeg", "coconut", "nutrition", "donut", "doughnut", "minute"],
        "cream": ["cream of tartar"],
        "bun": ["bunch"],
        "roe": ["romaine"],
        "sole": ["console"],
        "rye": ["dryer"],
    ]

    /// Returns the allergen words found in the text (empty = safe).
    static func violations(in texts: [String], allergies: [String]) -> [String] {
        let haystack = texts.joined(separator: " ").lowercased()
        return terms(for: allergies).filter { term in
            var h = haystack
            for ex in harmless[term] ?? [] { h = h.replacingOccurrences(of: ex, with: " ") }
            return h.contains(term)
        }.sorted()
    }
}
