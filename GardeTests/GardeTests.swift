import Testing
import Foundation
@testable import Garde

// These run on GitHub's Macs before every TestFlight upload. If any fail, nothing ships.

@Suite("Allergy filter") struct AllergenTests {
    func flagged(_ text: String, _ allergies: [String]) -> Bool { !AllergenGuard.violations(in: [text], allergies: allergies).isEmpty }

    @Test("Catches real allergens", arguments: [
        ("Garlic shrimp scampi", "shellfish"), ("Pad thai with peanuts", "peanuts"), ("Caesar salad", "fish"),
        ("Basil pesto pasta", "tree nut"), ("Seared sea bass", "fish"), ("Hummus plate", "sesame"), ("Ice cream", "dairy"),
        ("Lemon meringue", "egg"), ("Peanut butter toast", "nuts"), ("Spaghetti carbonara", "eggs"), ("Spaghetti carbonara", "gluten"),
        ("Fried calamari", "seafood"), ("Salmon", "seafood"), ("Shrimp", "crustaceans"), ("Caprese with burrata", "milk"),
        ("Caprese with burrata", "lactose"), ("Udon noodle soup", "wheat"), ("Satay skewers", "peanut"), ("Eggs benedict", "egg"),
        ("Almond croissant", "nuts"), ("Shrimp and grits", "Shellfish "),
    ])
    func catches(text: String, allergy: String) { #expect(flagged(text, [allergy])) }

    @Test("Doesn't cry wolf", arguments: [
        ("Roasted eggplant parmesan", "eggs"), ("Butternut squash soup", "dairy"), ("Coconut curry", "tree nuts"),
        ("Nutmeg-spiced apples", "nuts"), ("Grilled chicken, rice", "shellfish"), ("Bass", "shellfish"),
        ("Pancakes with butter", "peanut"), ("Peanut butter toast", "dairy"), ("Veggie stir fry", "egg"),
        ("Romaine salad", "fish"), ("Bunch of kale", "gluten"), ("Two minute noodles", "nuts"), ("Cream of tartar cookies", "dairy"),
    ])
    func noFalseAlarm(text: String, allergy: String) { #expect(!flagged(text, [allergy])) }
}

@Suite("Printed dates") struct DateTests {
    func ymd(_ d: Date?) -> String? {
        guard let d else { return nil }
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)   // local, like DateSniffer
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    @Test(arguments: [
        ("BEST BY 11/18/26", "2026-11-18"), ("EXP 2026-11-18", "2026-11-18"), ("USE BY NOV 18 2026", "2026-11-18"),
        ("18NOV26", "2026-11-18"), ("SELL BY 12.03.26", "2026-12-03"), ("BB 03 DEC 2026", "2026-12-03"),
        ("Best before January 5, 2027", "2027-01-05"), ("PACKED 10/30/26 USE BY 11/06/26", "2026-11-06"), ("Sept. 4, 2026", "2026-09-04"),
    ])
    func reads(text: String, expected: String) { #expect(ymd(DateSniffer.date(in: text)) == expected) }

    @Test(arguments: ["LOT 4471 2311", "EXP 11/26", "NOV 182026", "BEST BY FEB 30 2026"])
    func ignoresNonDates(text: String) { #expect(DateSniffer.date(in: text) == nil) }
}

@Suite("Cook-mode timers") struct TimerTests {
    @Test(arguments: [
        ("Simmer 10 minutes", 600), ("Bake for 1 hour", 3600), ("Rest 5-7 minutes", 420), ("Sear 3 to 4 mins per side", 240),
        ("Marinate 2 hrs", 7200), ("Boil 90 seconds", 90), ("Cook 1 1/2 hours", 5400), ("Roast 1.5 hours", 5400),
        ("Add 2 cups stock and simmer 20 minutes", 1200),
    ])
    func finds(step: String, seconds: Int) { #expect(CookVoice.duration(in: step) == seconds) }

    @Test(arguments: ["Season with salt", "Preheat oven to 425°F", "Add 1 minced shallot", "Add 3 shallots, minced"])
    func noTimer(step: String) { #expect(CookVoice.duration(in: step) == nil) }
}

@Suite("Receipts") struct ReceiptTests {
    @Test(arguments: [
        ("BNLS SKNLS CHKN THGH", "Boneless Skinless Chicken Thigh"), ("ORG BABY SPINACH", "Organic Baby Spinach"),
        ("LG BRWN EGGS 12CT", "Large Brown Eggs"), ("ATL SLMN FLT", "Atlantic Salmon Fillet"), ("SR CRM", "Sour Cream"),
        ("HVY CRM QT", "Heavy Cream Quart"), ("PB CRNCHY 16OZ", "Peanut Butter Crunchy"),
    ])
    func expandsAbbreviations(raw: String, expected: String) { #expect(ReceiptLexicon.expand(raw) == expected) }

    @Test func offlineReaderParsesStopAndShop() {
        let text = """
        STOP & SHOP
        BNLS SKNLS CHKN THGH  9.87 F
        ORG BABY SPINACH      4.99 F
        HOOD WHL MLK GAL      4.79 F
        STOP&SHOP SAVINGS     -1.00
        PLASTIC BAG FEE        0.10
        BAGELS PLN 6CT         4.29
        LG BRWN EGGS 12CT     5.49 F
        SUBTOTAL             28.53
        TAX                   0.00
        TOTAL                28.53
        VISA                 28.53
        """
        let scan = HeuristicParser.parse(text)
        #expect(scan.total == 28.53)
        #expect(scan.items.map(\.name) == ["Boneless Skinless Chicken Thigh", "Organic Baby Spinach", "Hood Whole Milk Gallon",
                                           "Bagels Plain", "Large Brown Eggs"])
        #expect(scan.items.first?.category == .poultry)
    }
}

@Suite("Store receipt layouts") struct StoreLayoutTests {
    @Test func costcoCodesAndDiscounts() {
        let scan = HeuristicParser.parse("""
        COSTCO WHOLESALE
        E 1234567 KS ORG EGGS 24CT  9.99 N
        E 7654321 ATL SLMN FLT  17.49 N
        /7654321  3.00-
        TOTAL 27.48
        """)
        #expect(scan.store == "Costco")
        #expect(scan.items.map(\.name) == ["Kirkland Signature Organic Eggs", "Atlantic Salmon Fillet"])
        #expect(abs((scan.items.last?.price ?? 0) - 14.49) < 0.001)
    }

    @Test func stopAndShopWeightLines() {
        let scan = HeuristicParser.parse("""
        STOP & SHOP
        BANANAS
        2.41 lb @ 0.69 /lb    1.66 F
        """)
        #expect(scan.items.first?.name == "Bananas")
        #expect(scan.items.first?.unit == "lb")
        #expect(scan.items.first?.quantity == 2.41)
    }

    @Test func traderJoesQuantityLines() {
        let scan = HeuristicParser.parse("""
        TRADER JOE'S
        ORGANIC BANANAS
        3 @ 0.29   0.87
        """)
        #expect(scan.store == "Trader Joe's")
        #expect(scan.items.first?.quantity == 3)
        #expect(scan.items.first?.price == 0.87)
    }

    @Test func walmartAndTargetCodes() {
        #expect(HeuristicParser.parse("Walmart\nGV WHOLE MILK 078742351870 F  3.12 N").items.first?.name == "Great Value Whole Milk")
        #expect(HeuristicParser.parse("TARGET\n071000140  GG SHRP CHDR  NF  $2.79").items.first?.name == "Good & Gather Sharp Cheddar")
    }
}

@Suite("Nutrition") struct NutritionTests {
    @Test func creamyChickenPasta() {
        let n = Nutrition.estimate(ingredients: ["1 1/2 lb boneless skinless chicken thighs", "2 tbsp olive oil", "4 cloves garlic, minced",
                                                 "1 cup chicken broth", "1/2 cup heavy cream", "1 cup grated parmesan", "8 oz penne",
                                                 "2 cups baby spinach", "Salt and pepper to taste"])
        #expect(n.isReliable)
        #expect(n.counted == 8)
        let per = n.perServing(4)
        #expect((550...800).contains(per.kcal))
        #expect((40...65).contains(per.protein))
    }

    @Test(arguments: [("1 eggplant", "eggplant"), ("2 tbsp peanut butter", "peanut butter"), ("1 cup chicken broth", "broth"),
                      ("1 tbsp unsalted butter", "butter"), ("1 can coconut milk", "coconut milk")])
    func picksTheRightFood(line: String, key: String) { #expect(Nutrition.food(for: line)?.keys.first == key) }

    @Test(arguments: ["Salt and pepper to taste", "1 bunch cilantro", "2 tsp smoked paprika"])
    func zeroCalorieItems(line: String) { #expect(Nutrition.isZero(line)) }
}

@Suite("Shelf life") struct ShelfLifeTests {
    @Test(arguments: [
        ("Boneless Skinless Chicken Thigh", 2), ("Eggplant", 7), ("Buttermilk", 14), ("Sliced Turkey", 14), ("Large Brown Eggs", 35), ("Hood Whole Milk Gallon", 7),
        ("Hamburger Buns", 10), ("Chopped Spinach", 5), ("Ribeye Steak", 4), ("Atlantic Salmon Fillet", 2), ("Fresh Mozzarella", 14),
        ("Strawberries", 4), ("Bacon", 7), ("Brie", 21),
    ])
    func fridgeDays(name: String, days: Int) {
        #expect(ShelfLife.days(name: name, category: .other, location: .fridge) == days)
    }

    @Test func openingShortensExpiration() {
        let sealed = Calendar.current.date(byAdding: .day, value: 30, to: .now)!
        let opened = ShelfLife.openedExpiration(name: "Heavy cream", category: .dairy, current: sealed)!
        #expect(opened < sealed)
        #expect(Calendar.current.dateComponents([.day], from: .now, to: opened).day! <= 7)
    }

    @Test(arguments: ["Chicken broth", "Beef broth", "Canned tomatoes", "Tomato paste", "Fish sauce", "Oyster sauce"])
    func pantryStaplesAreShelfStable(name: String) {
        #expect(ShelfLife.defaultLocation(for: .other, name: name) == .pantry)
        #expect(ShelfLife.days(name: name, category: .other, location: .pantry) >= 365)
    }

    @Test func peanutButterLivesInPantry() { #expect(ShelfLife.defaultLocation(for: .condiments, name: "Peanut Butter") == .pantry) }
}

@Suite("Shopping") struct ShoppingTests {
    @Test(arguments: [("Chicken thighs", FoodCategory.poultry), ("Shrimp", .seafood), ("Parmesan", .cheese), ("Lemons", .fruit),
                      ("Shallots", .produce), ("Sourdough bread", .bakery), ("Chicken broth", .canned), ("Peanut butter", .condiments)])
    func guessesAisle(name: String, category: FoodCategory) { #expect(ShoppingBrain.guessCategory(name) == category) }
}
