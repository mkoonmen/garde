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

@Suite("Nut allergy with exceptions") struct NutExceptionTests {
    let allergies = ["Tree nuts except almonds, hazelnuts"]
    @Test(arguments: ["Almond crusted chicken", "Nutella crepes", "Hazelnut coffee", "Peanut butter toast", "Thai coconut curry",
                      "Marzipan cookies", "Satay skewers", "Butternut squash soup", "Nutmeg spiced apples", "Nutritional yeast popcorn"])
    func safe(text: String) { #expect(AllergenGuard.violations(in: [text], allergies: allergies).isEmpty) }

    @Test(arguments: ["Basil pesto pasta", "Mixed nuts", "Cashew chicken", "Walnut brownies", "Pistachio gelato", "Pecan pie",
                      "Contains: nuts", "May contain tree nuts", "Macadamia cookies", "Roasted chestnuts", "Pine nut salad", "Praline",
                      "Almond and walnut cake", "Nocino old fashioned"])
    func blocked(text: String) { #expect(!AllergenGuard.violations(in: [text], allergies: allergies).isEmpty) }
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

@Suite("Allergies of several people") struct GuestAllergyTests {
    @Test func exceptionDoesNotCancelGuestAllergy() {
        #expect(!AllergenGuard.violations(in: ["Almond cake"], allergies: ["Tree nuts except almonds, hazelnuts", "almonds"]).isEmpty)
        #expect(AllergenGuard.violations(in: ["Almond cake"], allergies: ["Tree nuts except almonds, hazelnuts"]).isEmpty)
    }
    @Test(arguments: ["Pignoli cookies", "Nocello spritz", "Crème de noix"])
    func moreNuts(text: String) { #expect(!AllergenGuard.violations(in: [text], allergies: ["Tree nuts except almonds, hazelnuts"]).isEmpty) }
    @Test func pinotIsFine() { #expect(AllergenGuard.violations(in: ["Pinot noir braised short ribs"], allergies: ["Tree nuts except almonds, hazelnuts"]).isEmpty) }
}

@Suite("Recipe scaling") struct ScalingTests {
    @Test(arguments: [
        ("1 1/2 cups flour", 2.0, "3 cups flour"), ("1/2 cup heavy cream", 2.0, "1 cup heavy cream"), ("2 tbsp olive oil", 1.5, "3 tbsp olive oil"),
        ("1 14-oz can tomatoes", 2.0, "2 14-oz can tomatoes"), ("½ tsp salt", 2.0, "1 tsp salt"), ("3 eggs", 0.5, "1 1/2 eggs"),
        ("Salt and pepper to taste", 2.0, "Salt and pepper to taste"), ("2-3 cloves garlic", 2.0, "4-6 cloves garlic"),
        ("1-1/2 cups milk", 2.0, "3 cups milk"), ("1-inch piece ginger", 2.0, "1-inch piece ginger"), ("1 lb chicken thighs", 3.0, "3 lb chicken thighs"),
    ])
    func scales(line: String, factor: Double, expected: String) { #expect(RecipeScaler.scale(line, by: factor) == expected) }

    @Test(arguments: [("1 1/2 cups heavy cream, warmed", "heavy cream"), ("2 cloves garlic", "garlic"), ("1 14-oz can crushed tomatoes", "crushed tomatoes"),
                      ("1 lb chicken thighs (boneless)", "chicken thighs")])
    func foodNames(line: String, food: String) { #expect(RecipeScaler.foodName(line) == food) }
}

@Suite("Price book") struct PriceBookTests {
    @Test func sameKeyForVariants() {
        #expect(PriceBook.key("Organic Baby Spinach 5oz") == PriceBook.key("baby spinach"))
        #expect(PriceBook.key("Large Brown Eggs 12CT") == PriceBook.key("brown eggs"))
    }
    @Test func eggsDontMatchEggplant() {
        let e = PriceBook.Entry(key: "eggplant", name: "Eggplant", paid: [(date: .now, store: "ALDI", price: 1.99)])
        #expect(PriceBook.hint(for: "eggs", in: [e]) == nil)
    }
}

@Suite("Gmail filters") struct GmailFilterTests {
    @Test(arguments: [("Anthropic, PBC <invoice@stripe.com>", "Your receipt from Anthropic"), ("Qwen <noreply@qwen.ai>", "Payment receipt"),
                      ("Uber Receipts <noreply@uber.com>", "Your Thursday evening order with Uber Eats")])
    func notGrocery(from: String, subject: String) { #expect(EmailReceipt.groceryStore(from: from, subject: subject) == nil) }

    @Test func groceryStores() {
        #expect(EmailReceipt.groceryStore(from: "Walmart <help@walmart.com>", subject: "Your Walmart order receipt") == "Walmart")
        #expect(EmailReceipt.groceryStore(from: "Instacart <orders@instacart.com>", subject: "Your Stop & Shop receipt") != nil)
    }

    @Test(arguments: ["Your order has shipped", "Your package was delivered", "Rate your order", "Your order is ready for pickup"])
    func notices(subject: String) { #expect(EmailReceipt.isNotice(subject)) }

    @MainActor @Test func takeoutSenders() {
        #expect(Takeout.service(from: "DoorDash <no-reply@doordash.com>", subject: "Order confirmation for Michael from Thai Basil") == "DoorDash")
        #expect(Takeout.service(from: "McDonald's <mcdonalds@email.mcdonalds.com>", subject: "Your receipt") != nil)
        #expect(Takeout.service(from: "Uber <noreply@uber.com>", subject: "Your Thursday trip with Uber") == nil)
        #expect(Takeout.service(from: "DoorDash <no-reply@doordash.com>", subject: "Your DashMart order") == nil)
        #expect(Takeout.service(from: "DoorDash <no-reply@doordash.com>", subject: "Order confirmation from Rinaldi's Pizza") == "DoorDash")
    }
}

@Suite("Seasonal") struct SeasonalTests {
    @Test func everyMonthHasProduceAndNoTreeNuts() {
        for m in 1...12 {
            let list = Seasonal.byMonth[m] ?? []
            #expect(!list.isEmpty)
            #expect(AllergenGuard.violations(in: list, allergies: ["Tree nuts except almonds, hazelnuts"]).isEmpty)
        }
    }
}

@Suite("Taste profile") struct TasteProfileTests {
    @Test func wholeWords() {
        let logs = [CookLog(title: "Roasted eggplant parmesan", rating: 5), CookLog(title: "Smash burger", rating: 4), CookLog(title: "Shrimp pad thai", rating: 4)]
        let proteins = TasteProfile.rank(TasteProfile.proteins, home: logs, takeout: []).map(\.0)
        #expect(!proteins.contains("Eggs"))
        #expect(proteins.contains("Beef"))
        #expect(proteins.contains("Seafood"))
        #expect(TasteProfile.rank(TasteProfile.styles, home: logs, takeout: []).map(\.0).contains("Asian"))
    }
}

@Suite("Quick add") struct QuickAddTests {
    @Test func parsesASpokenList() {
        let l = QuickAdd.parse("eggs, 2 lb chicken thighs, a gallon of milk and baby spinach")
        #expect(l.map(\.name) == ["Eggs", "Chicken thighs", "Milk", "Baby spinach"])
        #expect(l[1].quantity == 2 && l[1].unit == "lb")
        #expect(l[2].unit == "gal")
        #expect(l[1].category == .poultry)
    }
    @Test func dozen() {
        #expect(QuickAdd.parse("a dozen eggs").first?.quantity == 12)
        #expect(QuickAdd.parse("half a dozen eggs").first?.quantity == 6)
        #expect(QuickAdd.parse("mac and cheese, milk").map(\.name) == ["Mac and cheese", "Milk"])
        #expect(QuickAdd.parse("milk and half and half").map(\.name) == ["Milk", "Half and half"])
    }
}

@Suite("Where to shop") struct BestStoreTests {
    @Test func picksCheapestStore() {
        let d = Date.now
        let e1 = PriceBook.Entry(key: PriceBook.key("Milk"), name: "Milk", paid: [(d, "ALDI", 3.0), (d, "Stop & Shop", 4.5)])
        let e2 = PriceBook.Entry(key: PriceBook.key("Eggs"), name: "Eggs", paid: [(d, "ALDI", 4.0), (d, "Stop & Shop", 5.0)])
        let pick = PriceBook.bestStore(for: ["milk", "eggs"], in: [e1, e2])
        #expect(pick?.store == "ALDI")
        #expect(pick?.cheapestFor == 2)
        #expect(abs((pick?.savings ?? 0) - 2.5) < 0.01)
    }
}

@Suite("Dinner timeline") struct DinnerTimelineTests {
    @Test func startsLongestFirst() {
        let serve = Date(timeIntervalSince1970: 1_000_000)
        let s = DinnerTimelineView.plan([("Risotto", 40), ("Short ribs", 180)], serveAt: serve)
        #expect(s.map(\.name) == ["Short ribs", "Risotto"])
        #expect(s[0].start == serve.addingTimeInterval(-185 * 60))
    }
}

@Suite("Holiday helpers") struct HolidayTests {
    @Test func thanksgiving2026() {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 6))!
        let d = HostView.nextThanksgiving(from: now)
        let c = Calendar.current.dateComponents([.month, .day], from: d)
        #expect(c.month == 11 && c.day == 26)
    }
    @Test func turkeyThaw() {
        let serve = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 16))!
        let start = HostView.thawStart(pounds: 14, serving: serve)
        #expect(Calendar.current.dateComponents([.month, .day], from: start).day == 22)
    }
}

@Suite("List check-off matching") struct CheckOffTests {
    @Test func wholeWords() {
        #expect(ShoppingBrain.sameFood("eggs", "large brown eggs"))
        #expect(ShoppingBrain.sameFood("whole milk", "milk"))
        #expect(!ShoppingBrain.sameFood("egg", "eggplant"))
        #expect(!ShoppingBrain.sameFood("oil", "foil"))
        #expect(!ShoppingBrain.words("peanut butter").isSubset(of: ShoppingBrain.words("butter")))
        #expect(ShoppingBrain.sameItem(list: "eggs", bought: "Large Brown Eggs"))
        #expect(ShoppingBrain.sameItem(list: "milk", bought: "Hood Whole Milk Gallon"))
        #expect(ShoppingBrain.sameItem(list: "milk", bought: "Whole Milk"))
        #expect(!ShoppingBrain.sameItem(list: "butter", bought: "Peanut Butter"))
        #expect(!ShoppingBrain.sameItem(list: "milk", bought: "Almond Milk"))
        #expect(!ShoppingBrain.sameItem(list: "eggs", bought: "Egg Noodles"))
    }
}

@Suite("Hidden tree nuts") struct HiddenNutTests {
    let a = ["Tree nuts except almonds, hazelnuts"]
    @Test(arguments: ["Mortadella sandwich", "Chicken korma", "Waldorf salad", "Chicken mole", "Baklava", "Gelato al pistacchio", "Pollo con nueces"])
    func blocked(text: String) { #expect(!AllergenGuard.violations(in: [text], allergies: a).isEmpty) }
    @Test(arguments: ["Guacamole and chips", "Pork pozole", "Gnocchi with sage butter", "Salsa con nuez moscada", "Gelato alla nocciola"])
    func fine(text: String) { #expect(AllergenGuard.violations(in: [text], allergies: a).isEmpty) }
}

@Suite("Offline swaps") struct SubstitutionTests {
    @Test func classics() {
        #expect(Substitutions.offline(for: "1 cup buttermilk") != nil)
        #expect(Substitutions.offline(for: "2 large eggs") != nil)
        #expect(Substitutions.offline(for: "1 eggplant") == nil)
        #expect(Substitutions.offline(for: "2 tbsp peanut butter") == nil)
        #expect(Substitutions.offline(for: "8 oz egg noodles") == nil)
    }
    @Test func nutSwapIsSafeForMichael() {
        let opts = Substitutions.offline(for: "1/2 cup walnuts")?.options ?? []
        #expect(opts.contains { AllergenGuard.violations(in: [$0], allergies: ["Tree nuts except almonds, hazelnuts"]).isEmpty })
    }
}

@Suite("Report card") struct ReportCardTests {
    @Test func perfectMonth() {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 20))!
        let logs = (0..<6).map { i -> CookLog in let l = CookLog(title: "Dish \(i)", rating: 5); l.date = now.addingTimeInterval(-Double(i) * 86_400); return l }
        let eaten = (0..<4).map { _ -> PantryItem in let p = PantryItem(name: "Milk"); p.isUsedUp = true; p.usedUpDate = now; return p }
        let card = ReportCard.make(items: eaten, logs: logs, takeout: [], spent: 200, budget: 600, now: now)
        #expect(card?.grade == "A")
    }
}

@Suite("Chef tips") struct ChefTipTests {
    @Test func matches() {
        #expect(ChefTips.tip(for: "Sear the chicken 6 minutes per side.") != nil)
        #expect(ChefTips.tip(for: "Serve and enjoy.") == nil)
        #expect(ChefTips.tip(for: "Add the rest of the broth") == nil)
        #expect(ChefTips.tip(for: "Add the pork chops") == nil)
    }
}

@Suite("Email parsing (iCloud / IMAP)") struct MIMETests {
    @Test func encodedSubject() {
        #expect(MIMEParser.decodeWords("=?UTF-8?Q?Your_Walmart_order_receipt?=") == "Your Walmart order receipt")
        #expect(MIMEParser.decodeWords("=?utf-8?B?WW91ciBUYXJnZXQgcmVjZWlwdA==?=") == "Your Target receipt")
    }
    @Test func multipartPrefersPlainText() {
        let raw = "Content-Type: multipart/alternative; boundary=\"XX\"\r\n\r\n--XX\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\nMilk 3.49=0ATotal 3.49\r\n--XX\r\nContent-Type: text/html\r\n\r\n<p>Milk</p>\r\n--XX--\r\n"
        let text = MIMEParser.bodyText(Data(raw.utf8))
        #expect(text.contains("Milk 3.49"))
        #expect(text.contains("Total 3.49"))
    }
    @Test func headersUnfold() {
        let h = MIMEParser.headers("From: Walmart\r\n <help@walmart.com>\r\nSubject: Receipt\r\n\r\n")
        #expect(h["from"] == "Walmart <help@walmart.com>")
        #expect(h["subject"] == "Receipt")
    }
}

@MainActor struct DrinkTaxonomyTests {
    @Test func oldRawValuesStillDecode() {
        for raw in ["red", "white", "rose", "sparkling", "dessert", "bourbon", "whiskey", "tequila", "rum", "gin", "vodka", "other"] {
            #expect(BottleKind(rawValue: raw) != nil)
        }
    }
    @Test func everyCategoryHasTypes() {
        for c in DrinkCategory.allCases { #expect(!c.kinds.isEmpty) }
        #expect(DrinkCategory.liquor.kinds.count >= 15)
        #expect(BottleKind.red.styles.contains("Pinot Noir"))
        #expect(BottleKind.ipa.hasFormat)
        #expect(!BottleKind.bourbon.hasFormat)
    }
    @Test func guessKind() {
        #expect(BottleReader.guessKind("White Claw Hard Seltzer Mango") == .seltzer)
        #expect(BottleReader.guessKind("Sierra Nevada Hazy IPA") == .ipa)
        #expect(BottleReader.guessKind("Lagavulin 16 Islay Single Malt Scotch") == .scotch)
        #expect(BottleReader.guessKind("Caymus Cabernet Sauvignon") == .red)
        #expect(BottleReader.guessKind("Del Maguey Mezcal") == .mezcal)
    }
}

@MainActor struct OpenedTests {
    @Test func ketchupMovesToFridgeAndShortens() {
        let k = PantryItem(name: "Heinz ketchup", category: .condiments, location: .pantry,
                           expirationDate: Calendar.current.date(byAdding: .day, value: 365, to: .now))
        #expect(ShelfLife.defaultLocation(for: .condiments, name: "Heinz ketchup") == .pantry)
        k.open()
        #expect(k.location == .fridge)
        #expect((k.daysLeft ?? 999) <= 181)
        k.unopen()
        #expect(k.location == .pantry)
        #expect((k.daysLeft ?? 0) > 300)
    }
    @Test func salsaJarIsTwoWeeksOpened() {
        let s = PantryItem(name: "Jarred salsa", category: .condiments, location: .pantry,
                           expirationDate: Calendar.current.date(byAdding: .day, value: 300, to: .now))
        s.open()
        #expect((s.daysLeft ?? 999) <= 14)
    }
    @Test func soySauceStaysInPantry() {
        #expect(!ShelfLife.needsFridgeAfterOpening(name: "Soy sauce", category: .condiments))
        #expect(ShelfLife.needsFridgeAfterOpening(name: "Mayonnaise", category: .condiments))
    }
}

struct NewCategoryTests {
    @Test func sortsSweetsCandyCoffeeBaking() {
        #expect(ShoppingBrain.guessCategory("Starbucks Hot Cocoa Mix") == .coffee)
        #expect(ShoppingBrain.guessCategory("Ghirardelli Triple Chocolate brownie mix") == .baking)
        #expect(ShoppingBrain.guessCategory("Watkins Pure Vanilla Extract") == .baking)
        #expect(ShoppingBrain.guessCategory("Reese's peanut butter cups candy") == .candy)
        #expect(ShoppingBrain.guessCategory("Chocolate chip cookies") == .baking || ShoppingBrain.guessCategory("Chocolate chip cookies") == .sweets)
        #expect(ShoppingBrain.guessCategory("Tea") == .coffee)
        #expect(ShoppingBrain.guessCategory("Ribeye steak") == .meat)
        #expect(ShoppingBrain.guessCategory("Cashew milk") == .beverages)
        #expect(ShoppingBrain.guessCategory("Tiramisu") == .sweets)
        #expect(ShoppingBrain.guessCategory("So Delicious Dairy Free coconut milk") == .beverages)
        #expect(ShoppingBrain.guessCategory("English muffins") == .bakery)
    }
}

@MainActor struct WasteCoachTests {
    @Test func flagsFoodsYouUsuallyToss() {
        func used(_ n: String, tossed: Bool) -> PantryItem {
            let i = PantryItem(name: n, category: .produce, location: .fridge, expirationDate: .now)
            i.markUsed(tossed: tossed); return i
        }
        let all = [used("Spinach", tossed: true), used("Baby spinach", tossed: true), used("Spinach", tossed: false), used("Spinach", tossed: true),
                   used("Eggs", tossed: false), used("Eggs", tossed: true)]
        let wasted = WasteCoach.oftenWasted(all)
        #expect(wasted.contains { $0.name.lowercased().contains("spinach") })
        #expect(!wasted.contains { $0.name == "Eggs" })
        #expect(WasteCoach.tip(for: "Spinach", wasted: wasted) != nil)
        #expect(WasteCoach.plannerNote(all).contains("pinach"))
    }
}
