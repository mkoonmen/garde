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
                     "praline", "marzipan", "nutella", "pesto", "frangipane", "gianduja", "nut butter", "amaretto",
                     "nut", "nuts", "chestnut", "nut oil", "nocino", "nocello", "noix", "pignoli", "pili nut", "piñon", "pinon", "hickory nut", "mortadella", "korma", "pasanda", "waldorf", "mole", "panforte", "torrone", "kulfi", "kaju", "malai kofta", "shahi", "fesenjan", "satsivi", "tarator", "marron", "pistacchi", "pistache", "pistacho", "nuez", "nueces", "noce", "noci", "anacard", "cajou", "akhrot", "nougat", "baklava", "romesco", "dukkah", "muhammara"],
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

    /// Foods made from a specific nut, so an exception covers them too ("almonds" also allows marzipan).
    static let madeFrom: [String: [String]] = [
        "almond": ["almond", "marzipan", "frangipane", "amaretto"],
        "hazelnut": ["hazelnut", "nutella", "gianduja", "filbert"],
        "peanut": ["peanut", "groundnut", "satay"],
        "coconut": ["coconut"],
        "pistachio": ["pistachio"], "cashew": ["cashew"], "walnut": ["walnut", "nocino", "nocello", "noix"], "pecan": ["pecan", "praline"],
        "macadamia": ["macadamia"], "pine nut": ["pine nut", "pignoli", "pesto", "piñon", "pinon"], "brazil nut": ["brazil nut"], "chestnut": ["chestnut"],
    ]

    /// Splits "Tree nuts except almonds, hazelnuts" into ("tree nuts", ["almond", "hazelnut"]).
    static func parse(_ raw: String) -> (allergy: String, safe: [String]) {
        let lower = raw.lowercased()
        guard let r = lower.range(of: " except") else { return (lower.trimmingCharacters(in: .whitespaces), []) }
        let allergy = String(lower[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
        let rest = lower[r.upperBound...].replacingOccurrences(of: ":", with: "").replacingOccurrences(of: " and ", with: ",")
        let safe = rest.split(separator: ",").map { w -> String in
            var t = w.trimmingCharacters(in: .whitespaces)
            if t.hasSuffix("s") { t.removeLast() }
            return t
        }.filter { !$0.isEmpty }
        return (allergy, safe)
    }

    /// Every word that is safe because of an exception (plus what's made from it).
    static func safeWords(for allergies: [String]) -> Set<String> {
        var out: Set<String> = []
        for raw in allergies { for s in parse(raw).safe { out.insert(s); madeFrom[s]?.forEach { out.insert($0) } } }
        return out
    }

    /// Expands the user's allergy list into every word to look for.
    static func terms(for allergies: [String]) -> [String] {
        var out: Set<String> = []
        let safe = safeWords(for: allergies)
        for raw in allergies {
            let a = parse(raw).allergy
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
        return Array(out.subtracting(safe))
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
        "noix": ["noix de coco", "noix de muscade"],
        "nuez": ["nuez moscada"],
        "noce": ["noce moscata"],
        "mole": ["guacamole", "molecule", "molest", "pozole"],
        "pinon": ["pinot"],
    ]

    /// Returns the allergen words found in the text (empty = safe).
    /// Each allergy is checked on its own, so one person's exception ("except almonds") never cancels
    /// someone else's allergy (a guest allergic to almonds).
    static func violations(in texts: [String], allergies: [String]) -> [String] {
        Array(Set(allergies.flatMap { violations(in: texts, single: $0) })).sorted()
    }

    private static func violations(in texts: [String], single allergy: String) -> [String] {
        let allergies = [allergy]
        let haystack = texts.joined(separator: " ").lowercased()
        let safe = safeWords(for: allergies)
        // Peanuts and coconut aren't tree nuts: unless listed as allergies, "peanut"/"coconut" never count as "nut".
        let listed = Set(allergies.map { parse($0).allergy })
        var notNut = safe
        if !listed.contains(where: { $0.contains("peanut") }) { notNut.formUnion(["peanut", "groundnut"]) }
        notNut.insert("coconut")
        return terms(for: allergies).filter { term in
            var h = haystack
            for ex in harmless[term] ?? [] { h = h.replacingOccurrences(of: ex, with: " ") }
            // Remove safe nut names first so "hazelnut" or "almond" doesn't trip "nut".
            if term == "nut" || term == "nuts" || term.hasSuffix(" nut") || term == "nut butter" || term == "nut oil" {
                for w in notNut.sorted(by: { $0.count > $1.count }) { h = h.replacingOccurrences(of: w, with: " ") }
            }
            return h.contains(term)
        }.sorted()
    }
}
