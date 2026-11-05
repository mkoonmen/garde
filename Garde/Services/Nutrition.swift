import Foundation

/// Offline nutrition estimates from ingredient lines ("1 1/2 lb chicken thighs", "2 tbsp olive oil").
/// Values are per 100 g, approximate USDA averages. Results are estimates and say how many ingredients were counted.
enum Nutrition {
    struct Food {
        let keys: [String]
        let kcal, protein, carbs, fat: Double   // per 100 g
        let gramsPerCup: Double?
        let gramsEach: Double?               // one "each" / clove / slice / can, where it makes sense
    }

    struct Totals {
        var kcal = 0.0, protein = 0.0, carbs = 0.0, fat = 0.0
        var counted = 0, total = 0
        func perServing(_ n: Int) -> Totals {
            let d = Double(max(n, 1))
            return Totals(kcal: kcal / d, protein: protein / d, carbs: carbs / d, fat: fat / d, counted: counted, total: total)
        }
        /// Shown only when most of the recipe was recognized.
        var isReliable: Bool { total > 0 && Double(counted) / Double(total) >= 0.6 }
    }

    /// Ordered: specific names before general ones.
    static let foods: [Food] = [
        // Look-alikes first ("chicken broth" isn't chicken, "eggplant" isn't egg, "peanut butter" isn't butter)
        .init(keys: ["broth", "stock", "bouillon"], kcal: 6, protein: 0.6, carbs: 0.4, fat: 0.2, gramsPerCup: 240, gramsEach: 960),
        .init(keys: ["coconut milk"], kcal: 230, protein: 2.3, carbs: 6, fat: 24, gramsPerCup: 226, gramsEach: 400),
        .init(keys: ["peanut butter", "almond butter"], kcal: 588, protein: 25, carbs: 20, fat: 50, gramsPerCup: 258, gramsEach: nil),
        .init(keys: ["butternut"], kcal: 45, protein: 1, carbs: 12, fat: 0.1, gramsPerCup: 140, gramsEach: 900),
        .init(keys: ["buttermilk"], kcal: 40, protein: 3.3, carbs: 4.8, fat: 0.9, gramsPerCup: 245, gramsEach: nil),
        .init(keys: ["eggplant"], kcal: 25, protein: 1, carbs: 6, fat: 0.2, gramsPerCup: 82, gramsEach: 450),
        .init(keys: ["cornstarch", "corn starch"], kcal: 381, protein: 0.3, carbs: 91, fat: 0.1, gramsPerCup: 128, gramsEach: nil),
        .init(keys: ["sweet potato"], kcal: 86, protein: 1.6, carbs: 20, fat: 0.1, gramsPerCup: 133, gramsEach: 130),
        // Proteins
        .init(keys: ["chicken thigh"], kcal: 121, protein: 19.7, carbs: 0, fat: 4.1, gramsPerCup: 140, gramsEach: 110),
        .init(keys: ["chicken breast"], kcal: 120, protein: 22.5, carbs: 0, fat: 2.6, gramsPerCup: 140, gramsEach: 200),
        .init(keys: ["chicken wing"], kcal: 191, protein: 17.5, carbs: 0, fat: 12.9, gramsPerCup: nil, gramsEach: 45),
        .init(keys: ["ground turkey"], kcal: 148, protein: 19.7, carbs: 0, fat: 7.7, gramsPerCup: 225, gramsEach: nil),
        .init(keys: ["chicken", "turkey"], kcal: 143, protein: 21, carbs: 0, fat: 6, gramsPerCup: 140, gramsEach: 150),
        .init(keys: ["ground beef", "hamburger"], kcal: 254, protein: 17.2, carbs: 0, fat: 20, gramsPerCup: 225, gramsEach: nil),
        .init(keys: ["ribeye"], kcal: 291, protein: 19, carbs: 0, fat: 23, gramsPerCup: nil, gramsEach: 340),
        .init(keys: ["sirloin", "flank", "skirt", "strip steak", "tenderloin", "filet mignon"], kcal: 160, protein: 21, carbs: 0, fat: 8, gramsPerCup: nil, gramsEach: 230),
        .init(keys: ["steak", "beef"], kcal: 217, protein: 20, carbs: 0, fat: 15, gramsPerCup: 140, gramsEach: 230),
        .init(keys: ["bacon"], kcal: 417, protein: 13, carbs: 1.4, fat: 40, gramsPerCup: nil, gramsEach: 28),
        .init(keys: ["prosciutto", "pancetta"], kcal: 250, protein: 26, carbs: 0, fat: 16, gramsPerCup: nil, gramsEach: 15),
        .init(keys: ["sausage", "chorizo"], kcal: 301, protein: 12, carbs: 2, fat: 27, gramsPerCup: nil, gramsEach: 75),
        .init(keys: ["pork chop", "pork tenderloin", "pork loin"], kcal: 172, protein: 21, carbs: 0, fat: 9, gramsPerCup: nil, gramsEach: 200),
        .init(keys: ["pork", "lamb"], kcal: 250, protein: 18, carbs: 0, fat: 20, gramsPerCup: 140, gramsEach: 200),
        .init(keys: ["salmon"], kcal: 208, protein: 20, carbs: 0, fat: 13, gramsPerCup: nil, gramsEach: 170),
        .init(keys: ["tuna"], kcal: 116, protein: 25.5, carbs: 0, fat: 0.8, gramsPerCup: 150, gramsEach: 140),
        .init(keys: ["shrimp", "prawn"], kcal: 85, protein: 20, carbs: 0, fat: 0.5, gramsPerCup: 145, gramsEach: 15),
        .init(keys: ["scallop"], kcal: 69, protein: 12, carbs: 3.2, fat: 0.5, gramsPerCup: nil, gramsEach: 30),
        .init(keys: ["cod", "halibut", "tilapia", "haddock", "flounder", "sole", "white fish", "bass", "snapper"], kcal: 90, protein: 19, carbs: 0, fat: 1.2, gramsPerCup: nil, gramsEach: 170),
        .init(keys: ["tofu"], kcal: 76, protein: 8, carbs: 1.9, fat: 4.8, gramsPerCup: 250, gramsEach: 400),
        .init(keys: ["egg white"], kcal: 52, protein: 11, carbs: 0.7, fat: 0.2, gramsPerCup: 243, gramsEach: 33),
        .init(keys: ["egg yolk"], kcal: 322, protein: 16, carbs: 3.6, fat: 27, gramsPerCup: nil, gramsEach: 17),
        .init(keys: ["egg"], kcal: 143, protein: 12.6, carbs: 0.7, fat: 9.5, gramsPerCup: 243, gramsEach: 50),
        // Dairy
        .init(keys: ["heavy cream", "whipping cream"], kcal: 340, protein: 2.8, carbs: 2.8, fat: 36, gramsPerCup: 238, gramsEach: nil),
        .init(keys: ["half and half", "half-and-half"], kcal: 131, protein: 3, carbs: 4.3, fat: 11.5, gramsPerCup: 242, gramsEach: nil),
        .init(keys: ["sour cream", "creme fraiche", "crème fraîche"], kcal: 198, protein: 2.4, carbs: 4.6, fat: 19, gramsPerCup: 230, gramsEach: nil),
        .init(keys: ["ice cream"], kcal: 207, protein: 3.5, carbs: 24, fat: 11, gramsPerCup: 132, gramsEach: nil),
        .init(keys: ["cream cheese", "boursin", "mascarpone"], kcal: 342, protein: 6, carbs: 4, fat: 34, gramsPerCup: 232, gramsEach: nil),
        .init(keys: ["cream"], kcal: 340, protein: 2.8, carbs: 2.8, fat: 36, gramsPerCup: 238, gramsEach: nil),
        .init(keys: ["greek yogurt"], kcal: 59, protein: 10, carbs: 3.6, fat: 0.4, gramsPerCup: 245, gramsEach: 170),
        .init(keys: ["yogurt"], kcal: 61, protein: 3.5, carbs: 4.7, fat: 3.3, gramsPerCup: 245, gramsEach: 170),
        .init(keys: ["butter"], kcal: 717, protein: 0.9, carbs: 0.1, fat: 81, gramsPerCup: 227, gramsEach: 113),
        .init(keys: ["milk"], kcal: 61, protein: 3.2, carbs: 4.8, fat: 3.3, gramsPerCup: 244, gramsEach: nil),
        .init(keys: ["parmesan", "parmigiano", "pecorino"], kcal: 431, protein: 38, carbs: 4.1, fat: 29, gramsPerCup: 100, gramsEach: nil),
        .init(keys: ["mozzarella", "burrata"], kcal: 280, protein: 28, carbs: 3, fat: 17, gramsPerCup: 113, gramsEach: 225),
        .init(keys: ["ricotta"], kcal: 174, protein: 11, carbs: 3, fat: 13, gramsPerCup: 246, gramsEach: nil),
        .init(keys: ["feta", "goat cheese"], kcal: 264, protein: 14, carbs: 4, fat: 21, gramsPerCup: 150, gramsEach: nil),
        .init(keys: ["cheddar", "gouda", "gruyere", "gruyère", "swiss", "cheese", "brie"], kcal: 390, protein: 24, carbs: 1.5, fat: 32, gramsPerCup: 113, gramsEach: nil),
        // Fats & sweeteners
        .init(keys: ["olive oil", "vegetable oil", "canola oil", "avocado oil", "sesame oil", "oil"], kcal: 884, protein: 0, carbs: 0, fat: 100, gramsPerCup: 216, gramsEach: nil),
        .init(keys: ["mayonnaise", "mayo", "aioli"], kcal: 680, protein: 1, carbs: 0.6, fat: 75, gramsPerCup: 220, gramsEach: nil),
        .init(keys: ["honey"], kcal: 304, protein: 0.3, carbs: 82, fat: 0, gramsPerCup: 339, gramsEach: nil),
        .init(keys: ["maple syrup"], kcal: 260, protein: 0, carbs: 67, fat: 0, gramsPerCup: 315, gramsEach: nil),
        .init(keys: ["brown sugar", "sugar"], kcal: 387, protein: 0, carbs: 100, fat: 0, gramsPerCup: 200, gramsEach: nil),
        // Grains & starches
        .init(keys: ["breadcrumb", "panko"], kcal: 395, protein: 13, carbs: 72, fat: 5, gramsPerCup: 108, gramsEach: nil),
        .init(keys: ["all-purpose flour", "flour"], kcal: 364, protein: 10, carbs: 76, fat: 1, gramsPerCup: 125, gramsEach: nil),
        .init(keys: ["cooked rice"], kcal: 130, protein: 2.7, carbs: 28, fat: 0.3, gramsPerCup: 158, gramsEach: nil),
        .init(keys: ["rice", "risotto", "arborio"], kcal: 360, protein: 6.6, carbs: 79, fat: 0.6, gramsPerCup: 185, gramsEach: nil),
        .init(keys: ["quinoa"], kcal: 368, protein: 14, carbs: 64, fat: 6, gramsPerCup: 170, gramsEach: nil),
        .init(keys: ["oats", "oatmeal"], kcal: 389, protein: 17, carbs: 66, fat: 7, gramsPerCup: 80, gramsEach: nil),
        .init(keys: ["gnocchi"], kcal: 133, protein: 3.6, carbs: 28, fat: 0.4, gramsPerCup: 150, gramsEach: nil),
        .init(keys: ["pasta", "spaghetti", "linguine", "penne", "rigatoni", "fettuccine", "orzo", "noodle", "macaroni"], kcal: 371, protein: 13, carbs: 75, fat: 1.5, gramsPerCup: 100, gramsEach: nil),
        .init(keys: ["tortilla"], kcal: 304, protein: 8, carbs: 50, fat: 8, gramsPerCup: nil, gramsEach: 45),
        .init(keys: ["bread", "baguette", "sourdough", "buns", "brioche", "dinner roll", "rolls", "pita", "naan"], kcal: 265, protein: 9, carbs: 49, fat: 3.2, gramsPerCup: 45, gramsEach: 30),
        .init(keys: ["potato"], kcal: 77, protein: 2, carbs: 17, fat: 0.1, gramsPerCup: 150, gramsEach: 213),
        // Beans
        .init(keys: ["chickpea", "garbanzo"], kcal: 164, protein: 8.9, carbs: 27, fat: 2.6, gramsPerCup: 164, gramsEach: 240),
        .init(keys: ["black bean", "kidney bean", "cannellini", "white bean", "beans", "lentil"], kcal: 132, protein: 8.9, carbs: 24, fat: 0.5, gramsPerCup: 172, gramsEach: 240),
        // Vegetables & fruit
        .init(keys: ["crushed tomato", "diced tomato", "canned tomato", "tomato sauce", "marinara"], kcal: 32, protein: 1.6, carbs: 7, fat: 0.3, gramsPerCup: 245, gramsEach: 400),
        .init(keys: ["tomato paste"], kcal: 82, protein: 4.3, carbs: 19, fat: 0.5, gramsPerCup: 262, gramsEach: 170),
        .init(keys: ["tomato"], kcal: 18, protein: 0.9, carbs: 3.9, fat: 0.2, gramsPerCup: 180, gramsEach: 123),
        .init(keys: ["shallot"], kcal: 72, protein: 2.5, carbs: 17, fat: 0.1, gramsPerCup: 160, gramsEach: 30),
        .init(keys: ["scallion", "green onion"], kcal: 32, protein: 1.8, carbs: 7.3, fat: 0.2, gramsPerCup: 100, gramsEach: 15),
        .init(keys: ["onion"], kcal: 40, protein: 1.1, carbs: 9.3, fat: 0.1, gramsPerCup: 160, gramsEach: 110),
        .init(keys: ["garlic"], kcal: 149, protein: 6.4, carbs: 33, fat: 0.5, gramsPerCup: 136, gramsEach: 3),
        .init(keys: ["ginger"], kcal: 80, protein: 1.8, carbs: 18, fat: 0.8, gramsPerCup: 96, gramsEach: 15),
        .init(keys: ["spinach", "arugula"], kcal: 23, protein: 2.9, carbs: 3.6, fat: 0.4, gramsPerCup: 30, gramsEach: nil),
        .init(keys: ["kale"], kcal: 35, protein: 2.9, carbs: 4.4, fat: 1.5, gramsPerCup: 67, gramsEach: nil),
        .init(keys: ["lettuce", "romaine", "spring mix", "greens"], kcal: 17, protein: 1.2, carbs: 3.3, fat: 0.3, gramsPerCup: 47, gramsEach: 300),
        .init(keys: ["broccoli", "cauliflower"], kcal: 34, protein: 2.8, carbs: 7, fat: 0.4, gramsPerCup: 91, gramsEach: 500),
        .init(keys: ["brussels"], kcal: 43, protein: 3.4, carbs: 9, fat: 0.3, gramsPerCup: 88, gramsEach: 19),
        .init(keys: ["asparagus", "green bean"], kcal: 25, protein: 2, carbs: 5, fat: 0.1, gramsPerCup: 134, gramsEach: 16),
        .init(keys: ["bell pepper", "red pepper", "green pepper", "jalapeño", "jalapeno", "pepper"], kcal: 26, protein: 1, carbs: 6, fat: 0.3, gramsPerCup: 149, gramsEach: 120),
        .init(keys: ["mushroom"], kcal: 22, protein: 3.1, carbs: 3.3, fat: 0.3, gramsPerCup: 70, gramsEach: 18),
        .init(keys: ["zucchini", "squash"], kcal: 17, protein: 1.2, carbs: 3.1, fat: 0.3, gramsPerCup: 124, gramsEach: 200),
        .init(keys: ["carrot"], kcal: 41, protein: 0.9, carbs: 10, fat: 0.2, gramsPerCup: 128, gramsEach: 61),
        .init(keys: ["celery"], kcal: 16, protein: 0.7, carbs: 3, fat: 0.2, gramsPerCup: 101, gramsEach: 40),
        .init(keys: ["cucumber"], kcal: 15, protein: 0.7, carbs: 3.6, fat: 0.1, gramsPerCup: 119, gramsEach: 300),
        .init(keys: ["corn"], kcal: 86, protein: 3.3, carbs: 19, fat: 1.4, gramsPerCup: 145, gramsEach: 90),
        .init(keys: ["peas"], kcal: 81, protein: 5.4, carbs: 14, fat: 0.4, gramsPerCup: 145, gramsEach: nil),
        .init(keys: ["avocado"], kcal: 160, protein: 2, carbs: 8.5, fat: 14.7, gramsPerCup: 150, gramsEach: 150),
        .init(keys: ["lemon juice", "lime juice"], kcal: 22, protein: 0.4, carbs: 6.9, fat: 0.2, gramsPerCup: 244, gramsEach: 30),
        .init(keys: ["lemon", "lime"], kcal: 29, protein: 1.1, carbs: 9.3, fat: 0.3, gramsPerCup: nil, gramsEach: 58),
        .init(keys: ["apple", "pear"], kcal: 52, protein: 0.3, carbs: 14, fat: 0.2, gramsPerCup: 125, gramsEach: 182),
        .init(keys: ["banana"], kcal: 89, protein: 1.1, carbs: 23, fat: 0.3, gramsPerCup: 150, gramsEach: 118),
        .init(keys: ["berries", "blueberr", "strawberr", "raspberr"], kcal: 50, protein: 0.8, carbs: 12, fat: 0.4, gramsPerCup: 148, gramsEach: nil),
        // Liquids & sauces
        .init(keys: ["white wine", "red wine", "wine"], kcal: 83, protein: 0.1, carbs: 2.6, fat: 0, gramsPerCup: 236, gramsEach: 750),
        .init(keys: ["soy sauce", "tamari"], kcal: 53, protein: 8, carbs: 4.9, fat: 0.6, gramsPerCup: 255, gramsEach: nil),
        .init(keys: ["almond", "walnut", "pecan", "cashew", "pistachio", "pine nut"], kcal: 600, protein: 18, carbs: 18, fat: 54, gramsPerCup: 140, gramsEach: nil),
    ]

    /// Ingredients that add ~nothing. They count as recognized (they don't hurt coverage). Matched as whole words,
    /// so "unsalted butter" isn't mistaken for salt.
    static let zeroWords = ["salt", "black pepper", "white pepper", "pepper to taste", "peppercorns?", "water", "ice", "parsley",
                            "cilantro", "basil", "thyme", "rosemary", "oregano", "dill", "mint", "chives?", "paprika", "cumin",
                            "chili flakes?", "red pepper flakes?", "pepper flakes?", "cinnamon", "nutmeg", "bay leaf", "bay leaves",
                            "spices?", "seasoning", "zest", "vinegar", "mustard", "hot sauce", "fish sauce", "worcestershire",
                            "baking soda", "baking powder", "vanilla", "cayenne", "turmeric", "coriander", "garnish", "cooking spray",
                            "garlic powder", "onion powder", "italian seasoning", "sage", "tarragon", "allspice", "cloves? \\(spice\\)"]
    static let zeroRegex = try! Regex("\\b(" + zeroWords.joined(separator: "|") + ")\\b").ignoresCase()

    /// True when the line is only a zero-calorie item (but "salt and pepper chicken" still counts the chicken).
    static func isZero(_ line: String) -> Bool {
        guard line.contains(zeroRegex) else { return false }
        let stripped = line.replacing(zeroRegex, with: "")
        return food(for: stripped) == nil
    }

    static func food(for line: String) -> Food? {
        let l = line.lowercased()
        return foods.first { $0.keys.contains(where: { l.contains($0) }) }
    }

    /// Parses "1 1/2", "½", "2-3" (uses the low end), "0.5". Defaults to 1.
    static func quantity(in line: String) -> Double {
        let l = line.lowercased()
            .replacingOccurrences(of: "½", with: " 1/2").replacingOccurrences(of: "¼", with: " 1/4")
            .replacingOccurrences(of: "¾", with: " 3/4").replacingOccurrences(of: "⅓", with: " 1/3")
            .replacingOccurrences(of: "⅔", with: " 2/3").replacingOccurrences(of: "⅛", with: " 1/8")
            .trimmingCharacters(in: .whitespaces)
        if let m = l.firstMatch(of: /^(\d+)\s+(\d+)\/(\d+)/), let w = Double(m.1), let n = Double(m.2), let d = Double(m.3), d > 0 { return w + n / d }
        if let m = l.firstMatch(of: /^(\d+)\/(\d+)/), let n = Double(m.1), let d = Double(m.2), d > 0 { return n / d }
        if let m = l.firstMatch(of: /^(\d+(?:\.\d+)?)\s*(?:-|to)\s*\d/), let a = Double(m.1) { return a }
        if let m = l.firstMatch(of: /^(\d+(?:\.\d+)?)/), let a = Double(m.1) { return a }
        if l.hasPrefix("a ") || l.hasPrefix("an ") || l.hasPrefix("one ") { return 1 }
        if l.hasPrefix("half") { return 0.5 }
        return 1
    }

    /// Grams for one ingredient line, or nil if it can't be worked out.
    static func grams(line: String, food: Food) -> Double? {
        let l = line.lowercased()
        let q = quantity(in: line)
        let unitPatterns: [(Regex<AnyRegexOutput>, Double?)] = [
            (try! Regex(#"\b(lbs?|pounds?)\b"#), 453.6),
            (try! Regex(#"\b(oz|ounces?)\b"#), 28.35),
            (try! Regex(#"\b(kg|kilograms?)\b"#), 1000),
            (try! Regex(#"\d\s*(g|grams?)\b"#), 1),
            (try! Regex(#"\b(cups?|c\.)\b"#), food.gramsPerCup),
            (try! Regex(#"\b(tablespoons?|tbsps?|tbs)\b"#), food.gramsPerCup.map { $0 / 16 }),
            (try! Regex(#"\b(teaspoons?|tsps?)\b"#), food.gramsPerCup.map { $0 / 48 }),
            (try! Regex(#"\b(ml|milliliters?)\b"#), food.gramsPerCup.map { $0 / 240 }),
            (try! Regex(#"\b(pinch|dash)\b"#), 0.5),
            (try! Regex(#"\b(cans?|jars?)\b"#), food.gramsEach ?? 400),
            (try! Regex(#"\b(stick)s?\b"#), 113),
        ]
        for (re, g) in unitPatterns where l.contains(re) {
            guard let g else { return nil }
            return q * g
        }
        // "3 cloves garlic", "2 chicken breasts", "4 slices bacon" → each
        if let each = food.gramsEach { return q * each }
        return nil
    }

    static func estimate(ingredients: [String]) -> Totals {
        var t = Totals()
        for line in ingredients {
            if isZero(line) { continue }
            t.total += 1
            let cleaned = line.replacing(zeroRegex, with: "")
            guard let f = food(for: cleaned), let g = grams(line: line, food: f) else { continue }
            let k = g / 100
            t.kcal += f.kcal * k; t.protein += f.protein * k; t.carbs += f.carbs * k; t.fat += f.fat * k
            t.counted += 1
        }
        return t
    }
}
