import Foundation

/// How long food lasts. Item-specific rules first (by keyword), then category defaults.
/// Days are conservative, based on USDA FoodKeeper-style guidance. Everything is editable per item.
enum ShelfLife {
    struct Rule {
        let keywords: [String]
        let fridge: Int?
        let freezer: Int?
        let pantry: Int?     // also used for counter
        let opened: Int?     // days once opened (in its normal spot)
    }

    /// Ordered: the first rule whose keyword appears in the item name wins, so specific cuts come before general words.
    static let rules: [Rule] = [
        // Look-alikes first (names that contain another food's keyword)
        .init(keywords: ["broth", "stock", "bouillon"], fridge: nil, freezer: 90, pantry: 365, opened: 4),
        .init(keywords: ["marinara", "tomato sauce", "pasta sauce", "tomato paste", "canned tomato", "crushed tomato", "san marzano"], fridge: nil, freezer: 120, pantry: 365, opened: 5),
        .init(keywords: ["fish sauce", "oyster sauce", "worcestershire", "soy sauce", "hot sauce", "sriracha"], fridge: nil, freezer: nil, pantry: 730, opened: 365),
        .init(keywords: ["goldfish", "cracker"], fridge: nil, freezer: nil, pantry: 180, opened: 30),
        .init(keywords: ["buttermilk"], fridge: 14, freezer: 90, pantry: nil, opened: 10),
        .init(keywords: ["deli", "sliced turkey", "sliced chicken", "turkey breast slice", "salami", "prosciutto", "lunch meat", "cold cut"], fridge: 14, freezer: 60, pantry: nil, opened: 5),
        .init(keywords: ["eggplant"], fridge: 7, freezer: nil, pantry: 2, opened: 2),
        .init(keywords: ["peanut butter", "almond butter", "nut butter"], fridge: 180, freezer: nil, pantry: 180, opened: 90),
        .init(keywords: ["butternut"], fridge: 30, freezer: 240, pantry: 30, opened: 5),
        .init(keywords: ["coconut milk", "evaporated milk", "condensed milk"], fridge: nil, freezer: nil, pantry: 365, opened: 5),
        .init(keywords: ["hamburger bun", "hot dog bun", "slider bun"], fridge: 10, freezer: 90, pantry: 5, opened: 5),
        .init(keywords: ["orange juice", "apple juice", "lemon juice", "lime juice"], fridge: 10, freezer: 240, pantry: 270, opened: 7),
        .init(keywords: ["vinegar"], fridge: nil, freezer: nil, pantry: 730, opened: 730),
        .init(keywords: ["oats", "oatmeal", "rolled", "cereal", "granola"], fridge: nil, freezer: nil, pantry: 365, opened: 180),
        .init(keywords: ["black pepper", "peppercorn", "pepperoni"], fridge: 30, freezer: nil, pantry: 365, opened: 30),
        .init(keywords: ["cornstarch", "corn tortilla", "cornmeal"], fridge: nil, freezer: nil, pantry: 365, opened: 180),
        .init(keywords: ["roasted red pepper", "chopped tomato", "diced tomato"], fridge: nil, freezer: nil, pantry: 365, opened: 7),
        .init(keywords: ["frozen"], fridge: 3, freezer: 240, pantry: nil, opened: 3),
        // Poultry
        .init(keywords: ["ground chicken", "ground turkey"], fridge: 2, freezer: 120, pantry: nil, opened: 2),
        .init(keywords: ["rotisserie"], fridge: 4, freezer: 120, pantry: nil, opened: 4),
        .init(keywords: ["chicken", "turkey", "duck"], fridge: 2, freezer: 270, pantry: nil, opened: 2),
        // Meat
        .init(keywords: ["ground beef", "ground pork", "ground lamb", "burger"], fridge: 2, freezer: 120, pantry: nil, opened: 2),
        .init(keywords: ["bacon"], fridge: 7, freezer: 30, pantry: nil, opened: 7),
        .init(keywords: ["hot dog", "frank"], fridge: 14, freezer: 60, pantry: nil, opened: 7),
        .init(keywords: ["sausage"], fridge: 2, freezer: 60, pantry: nil, opened: 2),
        .init(keywords: ["ham"], fridge: 7, freezer: 60, pantry: nil, opened: 5),
        .init(keywords: ["steak", "ribeye", "sirloin", "tenderloin", "pot roast", "beef roast", "pork roast", "pork chop", "lamb chop", "lamb", "veal", "beef", "pork"], fridge: 4, freezer: 240, pantry: nil, opened: 4),
        // Seafood
        .init(keywords: ["smoked salmon", "lox"], fridge: 14, freezer: 60, pantry: nil, opened: 7),
        .init(keywords: ["shrimp", "scallop", "crab", "lobster"], fridge: 2, freezer: 180, pantry: nil, opened: 2),
        .init(keywords: ["clam", "mussel", "oyster"], fridge: 2, freezer: 90, pantry: nil, opened: 1),
        .init(keywords: ["salmon", "tuna steak", "cod", "halibut", "tilapia", "fish", "swordfish", "bass", "flounder"], fridge: 2, freezer: 180, pantry: nil, opened: 2),
        .init(keywords: ["canned tuna", "tuna can", "sardine", "anchov"], fridge: nil, freezer: nil, pantry: 1095, opened: 3),
        // Dairy & eggs
        .init(keywords: ["egg"], fridge: 35, freezer: 365, pantry: nil, opened: 35),
        .init(keywords: ["heavy cream", "whipping cream", "half and half"], fridge: 21, freezer: 120, pantry: nil, opened: 7),
        .init(keywords: ["sour cream"], fridge: 21, freezer: nil, pantry: nil, opened: 14),
        .init(keywords: ["cream cheese"], fridge: 30, freezer: 60, pantry: nil, opened: 10),
        .init(keywords: ["butter"], fridge: 90, freezer: 270, pantry: 2, opened: 60),
        .init(keywords: ["oat milk", "almond milk"], fridge: 30, freezer: nil, pantry: 180, opened: 7),
        .init(keywords: ["milk"], fridge: 7, freezer: 90, pantry: nil, opened: 7),
        .init(keywords: ["yogurt", "kefir"], fridge: 14, freezer: 60, pantry: nil, opened: 7),
        .init(keywords: ["mozzarella", "burrata", "ricotta", "cottage", "mascarpone", "feta", "goat cheese", "boursin"], fridge: 14, freezer: 90, pantry: nil, opened: 5),
        .init(keywords: ["brie", "camembert"], fridge: 21, freezer: nil, pantry: nil, opened: 7),
        .init(keywords: ["shredded", "grated parm"], fridge: 30, freezer: 120, pantry: nil, opened: 7),
        .init(keywords: ["parmesan", "parmigiano", "pecorino", "aged", "cheddar", "gouda", "gruyere", "manchego", "cheese"], fridge: 60, freezer: 180, pantry: nil, opened: 28),
        // Produce
        .init(keywords: ["spinach", "arugula", "lettuce", "romaine", "spring mix", "salad"], fridge: 5, freezer: nil, pantry: nil, opened: 3),
        .init(keywords: ["basil", "cilantro", "parsley", "dill", "mint", "herb"], fridge: 7, freezer: 120, pantry: 2, opened: 7),
        .init(keywords: ["mushroom"], fridge: 6, freezer: nil, pantry: nil, opened: 4),
        .init(keywords: ["berries", "strawberr", "raspberr", "blackberr"], fridge: 4, freezer: 240, pantry: 1, opened: 3),
        .init(keywords: ["blueberr", "grape", "cherr"], fridge: 10, freezer: 240, pantry: 2, opened: 7),
        .init(keywords: ["avocado"], fridge: 5, freezer: nil, pantry: 4, opened: 1),
        .init(keywords: ["banana"], fridge: 5, freezer: 90, pantry: 5, opened: 1),
        .init(keywords: ["tomato"], fridge: 7, freezer: nil, pantry: 5, opened: 3),
        .init(keywords: ["apple", "pear"], fridge: 30, freezer: nil, pantry: 7, opened: 1),
        .init(keywords: ["lemon", "lime", "orange", "grapefruit", "citrus"], fridge: 28, freezer: nil, pantry: 7, opened: 4),
        .init(keywords: ["potato", "sweet potato", "yam"], fridge: nil, freezer: nil, pantry: 30, opened: 1),
        .init(keywords: ["onion", "shallot"], fridge: 30, freezer: nil, pantry: 30, opened: 7),
        .init(keywords: ["garlic"], fridge: nil, freezer: nil, pantry: 90, opened: 10),
        .init(keywords: ["carrot", "beet", "cabbage", "celery"], fridge: 21, freezer: nil, pantry: nil, opened: 14),
        .init(keywords: ["broccoli", "cauliflower", "asparagus", "zucchini", "squash", "pepper", "cucumber", "green bean", "corn", "kale", "brussels"], fridge: 5, freezer: 240, pantry: nil, opened: 3),
        .init(keywords: ["ginger"], fridge: 21, freezer: 180, pantry: 7, opened: 21),
        // Bakery & staples
        .init(keywords: ["bread", "bagel", "roll", "bun", "baguette", "sourdough", "pita", "tortilla"], fridge: 10, freezer: 90, pantry: 5, opened: 5),
        .init(keywords: ["fresh pasta", "gnocchi"], fridge: 14, freezer: 60, pantry: nil, opened: 3),
        .init(keywords: ["tofu"], fridge: 30, freezer: 150, pantry: nil, opened: 4),
        .init(keywords: ["hummus", "salsa", "guacamole", "dip"], fridge: 14, freezer: nil, pantry: nil, opened: 6),
        .init(keywords: ["mayo", "mayonnaise"], fridge: nil, freezer: nil, pantry: 120, opened: 60),
        .init(keywords: ["wine"], fridge: 5, freezer: nil, pantry: 730, opened: 4),
        .init(keywords: ["juice"], fridge: 10, freezer: 240, pantry: 270, opened: 7),
        .init(keywords: ["leftover"], fridge: 4, freezer: 90, pantry: nil, opened: 4),
    ]

    static func rule(for name: String) -> Rule? {
        let n = name.lowercased()
        return rules.first { $0.keywords.contains(where: { n.contains($0) }) }
    }

    static func days(for category: FoodCategory, in location: StorageLocation) -> Int {
        switch (category, location) {
        case (_, .freezer):
            switch category {
            case .seafood: return 90
            case .bakery: return 90
            default: return 180
            }
        case (.meat, _): return 3
        case (.poultry, _): return 2
        case (.seafood, _): return 2
        case (.deli, _): return 5
        case (.dairy, _): return 7
        case (.cheese, _): return 21
        case (.eggs, _): return 28
        case (.produce, .counter): return 5
        case (.produce, _): return 7
        case (.fruit, .counter): return 4
        case (.fruit, _): return 10
        case (.bakery, _): return 5
        case (.condiments, _): return 120
        case (.grains, _), (.canned, _), (.snacks, _): return 365
        case (.beverages, _): return 30
        case (.frozen, _): return 3
        case (.other, _): return 14
        }
    }

    /// Best estimate in days: item rule for that spot, else category default.
    static func days(name: String, category: FoodCategory, location: StorageLocation) -> Int {
        if let r = rule(for: name) {
            let d: Int? = switch location {
            case .fridge: r.fridge
            case .freezer: r.freezer
            case .pantry, .counter: r.pantry
            }
            if let d { return d }
        }
        return days(for: category, in: location)
    }

    static func estimatedExpiration(for category: FoodCategory, in location: StorageLocation, from purchase: Date = .now) -> Date {
        Calendar.current.date(byAdding: .day, value: days(for: category, in: location), to: purchase) ?? purchase
    }

    static func estimatedExpiration(name: String, category: FoodCategory, in location: StorageLocation, from purchase: Date = .now) -> Date {
        Calendar.current.date(byAdding: .day, value: days(name: name, category: category, location: location), to: purchase) ?? purchase
    }

    /// When something is opened, it may expire sooner than the package date.
    static func openedExpiration(name: String, category: FoodCategory, current: Date?, openedOn: Date = .now) -> Date? {
        let openedDays = rule(for: name)?.opened ?? (category == .condiments ? 60 : category == .canned ? 4 : nil)
        guard let openedDays, let byOpening = Calendar.current.date(byAdding: .day, value: openedDays, to: openedOn) else { return current }
        guard let current else { return byOpening }
        return min(current, byOpening)
    }

    /// Best-guess storage spot: item rule says where it keeps longest, else by category.
    static func defaultLocation(for category: FoodCategory, name: String = "") -> StorageLocation {
        if category == .frozen { return .freezer }
        if let r = rule(for: name) {
            // Keep it wherever it lasts longest; pantry wins ties (shelf-stable things like peanut butter).
            let pantry = r.pantry ?? 0, fridge = r.fridge ?? 0
            if pantry > 0 && pantry >= fridge { return .pantry }
            if fridge > 0 { return .fridge }
        }
        switch category {
        case .meat, .poultry, .seafood, .dairy, .cheese, .eggs, .deli, .produce, .condiments: return .fridge
        case .frozen: return .freezer
        case .fruit: return .counter
        default: return .pantry
        }
    }
}
