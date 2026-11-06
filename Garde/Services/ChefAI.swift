import Foundation
import FoundationModels
import SwiftData

// MARK: - Structured outputs the on-device model fills in

@Generable
struct ScannedItem {
    @Guide(description: "Plain grocery name a person would say, e.g. 'Chicken thighs', 'Whole milk'. Expand receipt abbreviations.")
    var name: String
    @Guide(description: "One of: meat, seafood, poultry, dairy, cheese, eggs, produce, fruit, bakery, grains, canned, condiments, frozen, beverages, snacks, deli, other")
    var category: String
    @Guide(description: "Count or amount, default 1")
    var quantity: Double
    @Guide(description: "Unit such as each, lb, oz, gal, pack, bunch")
    var unit: String
    @Guide(description: "Line price in dollars, or 0 if unknown")
    var price: Double
    @Guide(description: "Expiration or best-by date printed on the item in YYYY-MM-DD, or empty if none is visible")
    var printedExpiration: String
}

@Generable
struct ScanResult {
    @Guide(description: "Store name if this is a receipt, otherwise empty")
    var store: String
    @Guide(description: "Receipt total in dollars, or 0")
    var total: Double
    @Guide(description: "Only real food or drink items. Skip tax, bag fees, coupons, totals, payment lines and non-food.")
    var items: [ScannedItem]
}

@Generable
struct RecipeIdea {
    var title: String
    @Guide(description: "One appetizing sentence")
    var summary: String
    var minutes: Int
    var servings: Int
    @Guide(description: "Each ingredient with an amount, e.g. '1 lb chicken thighs'")
    var ingredients: [String]
    @Guide(description: "Clear numbered-style cooking steps, one action each")
    var steps: [String]
    @Guide(description: "Which items from the kitchen inventory this uses")
    var usesFromKitchen: [String]
}

@Generable
struct PlannedDinner {
    @Guide(description: "Day number starting at 0 for the first day of the plan")
    var dayIndex: Int
    var recipe: RecipeIdea
    @Guide(description: "Ingredients this dinner needs that are NOT in the kitchen inventory or spices, as short grocery names")
    var needToBuy: [String]
}

@Generable
struct WeekPlan {
    var dinners: [PlannedDinner]
}

@Generable
struct DinnerSketch {
    @Guide(description: "Day number starting at 0")
    var dayIndex: Int
    var title: String
    @Guide(description: "The 2–4 main ingredients")
    var keyIngredients: [String]
}

@Generable
struct WeekOutline {
    var dinners: [DinnerSketch]
}

@Generable
struct DinnerRecipe {
    var recipe: RecipeIdea
    @Guide(description: "Ingredients this dinner needs that are NOT in the kitchen inventory or spices, as short grocery names")
    var needToBuy: [String]
}

/// App-side plan result (plain struct, built from the model's pieces).
struct PlanResult {
    var dayIndex: Int
    var recipe: RecipeIdea
    var needToBuy: [String]
}

@Generable
struct HostMenu {
    @Guide(description: "Three to five courses in serving order")
    var courses: [HostCourse]
    @Guide(description: "Prep timeline from days before to serving, each a short line like 'Day before: make the dessert'")
    var timeline: [String]
    @Guide(description: "Groceries to buy that are not already in the kitchen, each with an amount for the whole party")
    var shoppingList: [String]
}

@Generable
struct HostCourse {
    @Guide(description: "Course name, e.g. 'Starter', 'Main', 'Side', 'Dessert'")
    var course: String
    @Guide(description: "Dish name")
    var dish: String
    @Guide(description: "One sentence: what it is and what can be made ahead")
    var note: String
}

@Generable
struct CocktailList {
    @Guide(description: "Three to five cocktails that can be made with the bottles listed (plus common pantry items)")
    var drinks: [Cocktail]
}

@Generable
struct Cocktail {
    @Guide(description: "Cocktail name")
    var name: String
    @Guide(description: "Spec lines with amounts, e.g. '2 oz bourbon', '3/4 oz lemon juice'")
    var spec: [String]
    @Guide(description: "One or two sentences on how to make it, including glass and garnish")
    var method: String
    @Guide(description: "Anything missing that they would need to buy, or empty")
    var missing: [String]
}

@Generable
struct Flight {
    @Guide(description: "Three or four bottles from the list in tasting order, each as 'Bottle name: what to notice'")
    var pours: [String]
    @Guide(description: "One or two sentences on why this order works")
    var why: String
    @Guide(description: "Two to four simple snacks to set out with the flight")
    var snacks: [String]
}

@Generable
struct Plating {
    @Guide(description: "Three to five short steps to plate the dish like a fine-dining restaurant: plate choice, sauce, placement, height, finishing")
    var steps: [String]
    @Guide(description: "One finishing touch using something likely already in the kitchen (herb, oil, flaky salt, citrus zest)")
    var garnish: String
}

@Generable
struct Swaps {
    @Guide(description: "Two to four substitutes, each a short ingredient line with an amount, e.g. '1/2 cup Greek yogurt + 1 tbsp milk'")
    var options: [String]
    @Guide(description: "One short sentence on how the dish changes")
    var note: String
}

@Generable
struct Pairing {
    @Guide(description: "Exact name of the bottle from the list, or empty if nothing on hand fits")
    var bottleFromCellar: String
    @Guide(description: "One or two sentences on why it works with this dish")
    var why: String
    @Guide(description: "A style to buy if nothing on hand is a good match, e.g. 'Oregon Pinot Noir'")
    var ifBuying: String
}

@Generable
struct RecipeBatch {
    @Guide(description: "Distinct recipe ideas", .count(3))
    var recipes: [RecipeIdea]
}

// MARK: - Plain app-side types (decoupled from the model's @Generable types)

struct ParsedItem: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var category: FoodCategory
    var quantity: Double
    var unit: String
    var price: Double?
    var printedExpiration: Date?
    var include = true
}

struct ParsedScan {
    var store: String
    var total: Double?
    var items: [ParsedItem]

    init(store: String, total: Double?, items: [ParsedItem]) {
        self.store = store; self.total = total; self.items = items
    }

    init(_ r: ScanResult) {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        store = r.store
        total = r.total > 0 ? r.total : nil
        items = r.items.map {
            ParsedItem(name: $0.name,
                       category: FoodCategory(rawValue: $0.category.lowercased()) ?? ShoppingBrain.guessCategory($0.name),
                       quantity: $0.quantity > 0 ? $0.quantity : 1,
                       unit: $0.unit.isEmpty ? "each" : $0.unit,
                       price: $0.price > 0 ? $0.price : nil,
                       printedExpiration: fmt.date(from: $0.printedExpiration))
        }
    }
}

// MARK: - Chef brain

@MainActor
@Observable
final class ChefAI {
    enum State: Equatable { case available, unavailable(String) }

    var state: State {
        if ChefEngine.shared.usingLocal { return .available }
        switch SystemLanguageModel.default.availability {
        case .available: return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return .unavailable("This iPhone doesn't support Apple Intelligence.")
            case .appleIntelligenceNotEnabled: return .unavailable("Turn on Apple Intelligence in Settings to use the chef.")
            case .modelNotReady: return .unavailable("The on-device model is still downloading. Try again shortly.")
            @unknown default: return .unavailable("The on-device model isn't available right now.")
            }
        }
    }

    // MARK: Scan parsing

    /// Turns OCR text (+ optional Vision labels) into structured grocery items.
    func parseScan(text: String, labels: [String]) async -> ParsedScan {
        guard state == .available else { return HeuristicParser.parse(text) }
        let session = ChefEngine.shared.session(instructions: """
        You read grocery receipts, food labels and photos of food, and extract the food items.
        Receipts use cryptic abbreviations; expand them to normal names (e.g. 'BNLS SKNLS CHKN THGH' -> 'Boneless skinless chicken thighs').
        Never invent items that are not in the text or labels.
        """)
        let prompt = """
        Today is \(Date.now.formatted(date: .numeric, time: .omitted)).
        Text read from the photo:
        \(text.isEmpty ? "(no text)" : String(text.prefix(4000)))

        Receipt abbreviations found (use these meanings): \(ReceiptLexicon.hints(for: text).ifEmpty("none"))

        Objects recognized in the photo: \(labels.isEmpty ? "(none)" : labels.joined(separator: ", "))
        """
        do {
            return ParsedScan(try await session.respond(to: prompt, generating: ScanResult.self).content)
        } catch {
            return HeuristicParser.parse(text)
        }
    }

    // MARK: Recipes

    struct RecipeRequest {
        var mood: String = ""          // "something cozy", "date night", "quick lunch"
        var maxMinutes: Int = 45
        var mustUse: [String] = []
        var noShopping = false         // only what's already in the kitchen
    }

    /// Generates recipes from what's in the kitchen, prioritizing what expires first.
    /// Any recipe that mentions an allergen is discarded by `AllergenGuard`.
    func suggestRecipes(items: [PantryItem], spices: [Spice], profile: KitchenProfile, logs: [CookLog] = [], request: RecipeRequest) async throws -> (recipes: [RecipeIdea], blocked: Int) {
        guard state == .available else { return ([], 0) }

        let active = items.filter { !$0.isUsedUp }
            .sorted { ($0.daysLeft ?? 999) < ($1.daysLeft ?? 999) }
        let inventory = inventoryText(active, limit: 30)
        let spiceList = spices.filter { $0.level != .empty }.map(\.name).joined(separator: ", ")

        let session = ChefEngine.shared.session(instructions: baseInstructions(profile: profile, logs: logs))

        let prompt = """
        Kitchen inventory (soonest-expiring first):
        \(inventory.ifEmpty("(empty)"))

        Spices on hand: \(spiceList.ifEmpty("basic only"))

        \(request.mustUse.isEmpty ? "" : "Must use: \(request.mustUse.joined(separator: ", "))")
        Mood: \(request.mood.ifEmpty("chef's choice"))
        Max time: \(request.maxMinutes) minutes.
        \(request.noShopping ? "NO SHOPPING: use only the inventory and spices above plus water, salt, pepper and cooking oil." : "")
        Suggest 3 different dishes.
        """

        let batch = try await session.respond(to: prompt, generating: RecipeBatch.self).content
        let never = Set(logs.filter(\.neverAgain).map { $0.title.lowercased() })
        let safe = batch.recipes.filter {
            AllergenGuard.violations(in: [$0.title] + $0.ingredients + $0.steps, allergies: profile.allergies).isEmpty
        }
        return (safe.filter { !never.contains($0.title.lowercased()) }, batch.recipes.count - safe.count)
    }


    // MARK: Shared prompt pieces

    func inventoryText(_ active: [PantryItem], limit: Int = 60) -> String {
        active.prefix(limit).map { item -> String in
            let d = item.daysLeft.map { $0 < 0 ? "EXPIRED" : "\($0)d left" } ?? "no date"
            let tag = item.isLeftover ? " [LEFTOVER, already cooked]" : ""
            return "- \(item.name)\(tag) (\(formatQty(item.quantity)) \(item.unit), \(item.location.label), \(d))"
        }.joined(separator: "\n")
    }

    /// Turns cook ratings into taste guidance.
    func tasteText(_ logs: [CookLog]) -> String {
        let recent = logs.sorted { $0.date > $1.date }.prefix(40)
        let loved = recent.filter { $0.rating >= 4 }.map(\.title)
        let meh = recent.filter { $0.rating > 0 && $0.rating <= 2 && !$0.neverAgain }.map(\.title)
        let never = recent.filter(\.neverAgain).map(\.title)
        let changes = recent.filter { !$0.wouldChange.isEmpty }.prefix(8).map { "\($0.title): \($0.wouldChange)" }
        var out: [String] = []
        if !loved.isEmpty { out.append("Dishes they rated highly (make more like these): \(loved.joined(separator: "; "))") }
        if !meh.isEmpty { out.append("Dishes they found mediocre: \(meh.joined(separator: "; "))") }
        if !never.isEmpty { out.append("Never suggest these again: \(never.joined(separator: "; "))") }
        if !changes.isEmpty { out.append("Their feedback: \(changes.joined(separator: " | "))") }
        return out.joined(separator: "\n")
    }

    func baseInstructions(profile: KitchenProfile, logs: [CookLog]) -> String {
        """
        You are a private chef cooking for one household from what they already have.
        ABSOLUTE RULE: never include these allergens or anything made from them: \(profile.allergies.isEmpty ? "none" : profile.allergies.joined(separator: "; ")).
        Foods named after "except" are safe. Never use unnamed "nuts", "mixed nuts" or nut oils when any nut allergy is listed.
        Avoid: \(profile.dislikes.joined(separator: ", ").ifEmpty("nothing")).
        They love: \(profile.loves.joined(separator: ", ").ifEmpty("anything good")).
        Diet notes: \(profile.dietNotes.ifEmpty("none")).
        Cooking level: \(profile.skillLevel). Default servings: \(profile.householdSize).
        Prefer ingredients that expire soonest. Assume salt, pepper, oil and water are available.
        Do not use EXPIRED items. LEFTOVER items are already-cooked dishes: transform them into something new rather than just reheating.
        Write steps with explicit times when there's waiting, e.g. 'Simmer 10 minutes'.
        \(tasteText(logs))
        \(Seasonal.hint)
        \(Takeout.tasteHint((try? GardeStore.container.mainContext.fetch(FetchDescriptor<TakeoutOrder>())) ?? []))
        """
    }

    // MARK: Weekly plan

    /// Plans dinners for the next `days` days, using soonest-expiring food first, and lists what has to be bought.
    /// Done in small steps (an outline, then one recipe per request) so it fits the on-device model's context window.
    /// Unsafe dinners are dropped.
    func planWeek(days: Int, items: [PantryItem], spices: [Spice], profile: KitchenProfile, logs: [CookLog], notes: String,
                  progress: ((Int, Int) -> Void)? = nil) async throws -> (dinners: [PlanResult], blocked: Int) {
        guard state == .available else { return ([], 0) }
        let active = items.filter { !$0.isUsedUp }.sorted { ($0.daysLeft ?? 999) < ($1.daysLeft ?? 999) }
        let inventory = inventoryText(active, limit: 25).ifEmpty("(empty)")
        let spiceList = spices.filter { $0.level != .empty }.map(\.name).prefix(20).joined(separator: ", ").ifEmpty("basic only")
        let start = Date.now.formatted(.dateTime.weekday(.wide).month().day())

        // 1. Outline: one short line per day.
        let outlineSession = ChefEngine.shared.session(instructions: baseInstructions(profile: profile, logs: logs))
        let outline = try await outlineSession.respond(to: """
        Sketch one dinner per day for \(days) days starting \(start) (dayIndex 0 to \(days - 1)). Titles and main ingredients only.
        Use the soonest-expiring food on the earliest days. Vary proteins and cuisines. Weeknights under 45 minutes.
        Frozen items need a night to thaw: don't put frozen meat or fish on day 0.
        \(DealsService.shared.plannerHint.isEmpty ? "" : "On sale near them this week (use these when buying): \(DealsService.shared.plannerHint)")
        \(notes.isEmpty ? "" : "Notes for this week: \(notes)")
        Kitchen (soonest-expiring first):
        \(inventory)
        """, generating: WeekOutline.self).content

        // 2. One full recipe per dinner, each in a fresh session.
        var results: [PlanResult] = []
        var blocked = 0
        let sketches = outline.dinners.sorted { $0.dayIndex < $1.dayIndex }.prefix(days)
        for (i, sketch) in sketches.enumerated() {
            progress?(i + 1, sketches.count)
            let session = ChefEngine.shared.session(instructions: baseInstructions(profile: profile, logs: logs))
            guard let dinner = try? await session.respond(to: """
            Write the full recipe for: \(sketch.title) (main ingredients: \(sketch.keyIngredients.joined(separator: ", "))).
            Kitchen (soonest-expiring first):
            \(inventory)
            Spices: \(spiceList)
            List anything not in the kitchen under needToBuy.
            """, generating: DinnerRecipe.self).content else { continue }
            let r = dinner.recipe
            if AllergenGuard.violations(in: [r.title] + r.ingredients + r.steps + dinner.needToBuy, allergies: profile.allergies).isEmpty {
                results.append(PlanResult(dayIndex: min(max(sketch.dayIndex, 0), days - 1), recipe: r, needToBuy: dinner.needToBuy))
            } else { blocked += 1 }
        }
        return (results, blocked)
    }

    // MARK: Pairing

    func pair(dish: String, ingredients: [String], bottles: [BarBottle]) async throws -> Pairing? {
        guard state == .available else { return nil }
        let cellar = bottles.filter { $0.count > 0 }.map { "- \($0.name) (\($0.kind.label)\($0.vintage.isEmpty ? "" : ", \($0.vintage)")\($0.region.isEmpty ? "" : ", \($0.region)"))" }
        let session = ChefEngine.shared.session(instructions: "You are a sommelier and bartender. Pair drinks with food. Only pick a bottle that is in the list.")
        let prompt = """
        Dish: \(dish)
        Main ingredients: \(ingredients.prefix(12).joined(separator: ", "))
        Bottles on hand:
        \(cellar.joined(separator: "\n").ifEmpty("(none)"))
        """
        var result = try await session.respond(to: prompt, generating: Pairing.self).content
        // Never claim a bottle they don't own.
        if !bottles.contains(where: { $0.name.caseInsensitiveCompare(result.bottleFromCellar) == .orderedSame }) {
            result.bottleFromCellar = ""
        }
        return result
    }

    /// A menu, prep timeline and shopping list for having people over. Checked against your allergies and the guests'.
    func hostMenu(guests: Int, occasion: String, guestAllergies: [String], items: [PantryItem], profile: KitchenProfile, logs: [CookLog]) async throws -> (menu: HostMenu?, blocked: Bool) {
        guard state == .available else { return (nil, false) }
        let all = profile.allergies + guestAllergies
        let session = ChefEngine.shared.session(instructions: baseInstructions(profile: profile, logs: logs) + """

        You are planning a dinner party. Guests' allergies are just as absolute: \(guestAllergies.isEmpty ? "none" : guestAllergies.joined(separator: "; ")).
        Favor dishes that can be made ahead so the host can enjoy the party.
        """)
        let prompt = """
        Occasion: \(occasion.ifEmpty("dinner with friends"))
        Guests (including host): \(guests)
        Already in the kitchen: \(items.prefix(30).map(\.name).joined(separator: ", "))
        """
        let menu = try await session.respond(to: prompt, generating: HostMenu.self).content
        let text = menu.courses.flatMap { [$0.dish, $0.note] } + menu.shoppingList + menu.timeline
        if !AllergenGuard.violations(in: text, allergies: all).isEmpty { return (nil, true) }
        return (menu, false)
    }

    /// Cocktails from the bar, using pantry citrus, sugar, herbs etc. Allergen-checked in code.
    func cocktails(bottles: [BarBottle], items: [PantryItem], profile: KitchenProfile, mood: String) async throws -> [Cocktail] {
        guard state == .available else { return [] }
        let spirits = bottles.filter { $0.count > 0 }.map { "\($0.name) (\($0.kind.label))" }
        let session = ChefEngine.shared.session(instructions: """
        You are a skilled bartender. Suggest classic and creative cocktails that use the bottles on hand.
        ABSOLUTE RULE: never include these allergens or anything made from them (including liqueurs): \(profile.allergies.isEmpty ? "none" : profile.allergies.joined(separator: "; ")).
        """)
        let prompt = """
        Bottles: \(spirits.joined(separator: ", ").ifEmpty("none"))
        Kitchen: \(items.prefix(40).map(\.name).joined(separator: ", "))
        Mood: \(mood.ifEmpty("bartender's choice"))
        Prefer drinks that need nothing extra.
        """
        let list = try await session.respond(to: prompt, generating: CocktailList.self).content
        return list.drinks.filter { AllergenGuard.violations(in: [$0.name, $0.method] + $0.spec + $0.missing, allergies: profile.allergies).isEmpty }
    }

    /// A guided tasting flight from bottles on hand (bourbon, whiskey, wine…). Snacks are allergen-checked.
    func flight(bottles: [BarBottle], profile: KitchenProfile) async throws -> Flight? {
        guard state == .available else { return nil }
        let list = bottles.filter { $0.count > 0 }.map { "- \($0.name) (\($0.kind.label)\($0.vintage.isEmpty ? "" : ", \($0.vintage)"))" }
        guard list.count >= 2 else { return nil }
        let session = ChefEngine.shared.session(instructions: """
        You are a spirits and wine educator leading a home tasting. Only use bottles from the list.
        Snacks must never include these allergens or anything made from them: \(profile.allergies.isEmpty ? "none" : profile.allergies.joined(separator: "; ")).
        """)
        var f = try await session.respond(to: "Bottles on hand:\n" + list.joined(separator: "\n"), generating: Flight.self).content
        let safe: (String) -> Bool = { AllergenGuard.violations(in: [$0], allergies: profile.allergies).isEmpty }
        f.snacks = f.snacks.filter(safe)
        f.pours = f.pours.filter(safe)
        if !safe(f.why) { f.why = "" }
        return f
    }

    /// How to plate a dish like a restaurant. Allergen-checked in code.
    func plating(dish: String, ingredients: [String], profile: KitchenProfile) async throws -> Plating? {
        guard state == .available else { return nil }
        let session = ChefEngine.shared.session(instructions: """
        You are a fine-dining chef teaching a home cook to plate beautifully with normal home dishes.
        Never add these allergens or anything made from them: \(profile.allergies.isEmpty ? "none" : profile.allergies.joined(separator: "; ")).
        """)
        let p = try await session.respond(to: "Dish: \(dish)\nIngredients: \(ingredients.prefix(15).joined(separator: ", "))", generating: Plating.self).content
        return AllergenGuard.violations(in: p.steps + [p.garnish], allergies: profile.allergies).isEmpty ? p : nil
    }

    /// Substitutes for one ingredient, preferring things already in the kitchen. Allergen-checked in code.
    func substitute(_ ingredient: String, dish: String, items: [PantryItem], profile: KitchenProfile) async throws -> Swaps? {
        guard state == .available else { return nil }
        let session = ChefEngine.shared.session(instructions: """
        You are a chef suggesting ingredient substitutions that keep a dish working.
        ABSOLUTE RULE: never suggest these allergens or anything made from them: \(profile.allergies.isEmpty ? "none" : profile.allergies.joined(separator: "; ")).
        """)
        let prompt = """
        Dish: \(dish)
        Replace: \(ingredient)
        In the kitchen now: \(items.prefix(30).map(\.name).joined(separator: ", "))
        Prefer substitutes from the kitchen list first.
        """
        var out = try await session.respond(to: prompt, generating: Swaps.self).content
        out.options = out.options.filter { AllergenGuard.violations(in: [$0], allergies: profile.allergies).isEmpty }
        return out.options.isEmpty ? nil : out
    }

    private func formatQty(_ q: Double) -> String {
        q == q.rounded() ? String(Int(q)) : String(format: "%.1f", q)
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

// MARK: - Fallback when Apple Intelligence is off

/// Simple line-by-line receipt parser used if the on-device model is unavailable.
/// Offline receipt reader. Knows the line layouts of the common chains:
/// Stop & Shop / King Kullen / ShopRite / Wegmans (name … price + tax flag, weight lines below),
/// Costco ("E 1234567 KS ORG EGGS 9.99 N", discounts as "/1234567 3.00-"),
/// Trader Joe's ("3 @ 0.29" quantity lines), Whole Foods ("365 OG …"), Walmart (UPC mid-line), Target ("$3.29").
enum HeuristicParser {
    static let skipWords = ["total", "subtotal", "tax", "change", "cash", "visa", "mastercard", "amex", "discover", "debit", "credit",
                            "balance", "savings", "saved", "coupon", "bag", "bags", "fee", "deposit", "thank", "card", "auth", "member",
                            "points", "approved", "tender", "tip", "delivery", "service", "refund", "void", "price you pay", "you saved",
                            "instant", "rebate", "reward", "loyalty", "account", "terminal", "cashier", "store", "receipt", "items sold"]

    static let stores: [(keys: [String], name: String)] = [
        (["stop & shop", "stop&shop", "stopandshop"], "Stop & Shop"), (["king kullen"], "King Kullen"),
        (["costco"], "Costco"), (["trader joe"], "Trader Joe's"), (["whole foods", "wholefoods"], "Whole Foods"),
        (["walmart", "wal-mart"], "Walmart"), (["target"], "Target"), (["wegmans"], "Wegmans"), (["shoprite"], "ShopRite"),
        (["bj's", "bjs wholesale"], "BJ's"), (["aldi"], "Aldi"), (["waldbaum"], "Waldbaum's"), (["iga"], "IGA"),
    ]

    static let priceAtEnd = /\$?\s?(-?\d{1,4}\.\d{2})(-)?\s*[A-Z]{0,2}\s*$/
    static let weightLine = /(\d+(?:\.\d+)?)\s*(lb|lbs|kg|oz)\s*@\s*\$?(\d+\.\d{2})/
    static let qtyLine = /^\s*(\d+)\s*@\s*\$?(\d+\.\d{2})/

    static func cleanName(_ raw: String) -> String {
        var t = raw
        t = t.replacing(/^\s*[A-Z]\s+(?=\d{3,})/, with: "")      // Costco leading "E "
        t = t.replacing(/^\s*\d{3,}\s+/, with: "")                 // leading item code
        t = t.replacing(/\s+\d{8,}\b/, with: " ")                  // Walmart / Target UPC mid-line
        t = t.replacing(/\s+(NF|TF|F|T|N|B|X)\s*$/, with: "")       // tax flags
        return t.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    static func parse(_ text: String) -> ParsedScan {
        var items: [ParsedItem] = []
        var total = 0.0
        var pendingName: String?
        let lines = text.split(separator: "\n").map(String.init)
        let lowerAll = text.lowercased()
        let store = stores.first { $0.keys.contains(where: { lowerAll.contains($0) }) }?.name
            ?? lines.first(where: { $0.rangeOfCharacter(from: .letters) != nil })?.capitalized ?? ""

        func add(_ rawName: String, price: Double, qty: Double = 1, unit: String = "each") {
            let name = ReceiptLexicon.expand(cleanName(rawName))
            guard name.count >= 3 else { return }
            items.append(ParsedItem(name: name, category: ShoppingBrain.guessCategory(name), quantity: qty, unit: unit,
                                    price: price, printedExpiration: nil))
        }

        for line in lines {
            let lower = line.lowercased()
            let words = Set(lower.split(whereSeparator: { !$0.isLetter }).map(String.init))

            // Weight line under an item: "1.32 lb @ 3.99 /lb   5.27"
            if let w = line.firstMatch(of: weightLine) {
                let qty = Double(w.1) ?? 1
                let unit = String(w.2).lowercased().hasPrefix("lb") ? "lb" : String(w.2).lowercased()
                let linePrice = line.firstMatch(of: priceAtEnd).flatMap { Double($0.1) } ?? (qty * (Double(w.3) ?? 0))
                if let name = pendingName { add(name, price: linePrice, qty: qty, unit: unit); pendingName = nil }
                else if var last = items.popLast() { last.quantity = qty; last.unit = unit; items.append(last) }
                continue
            }
            // Quantity line: "3 @ 0.29   0.87" (Trader Joe's and others)
            if let q = line.firstMatch(of: qtyLine), line.rangeOfCharacter(from: .letters) == nil || words.isEmpty {
                let qty = Double(q.1) ?? 1
                let linePrice = line.firstMatch(of: priceAtEnd).flatMap { Double($0.1) } ?? qty * (Double(q.2) ?? 0)
                if let name = pendingName { add(name, price: linePrice, qty: qty); pendingName = nil }
                else if var last = items.popLast() { last.quantity = qty; last.price = linePrice; items.append(last) }
                continue
            }

            guard let m = line.firstMatch(of: priceAtEnd), var price = Double(m.1) else {
                // A name with no price: the price is probably on the next (weight/qty) line.
                let candidate = cleanName(line)
                if candidate.count >= 3, candidate.rangeOfCharacter(from: .letters) != nil,
                   !skipWords.contains(where: { $0.contains(" ") ? lower.contains($0) : words.contains($0) }) {
                    pendingName = candidate
                } else { pendingName = nil }
                continue
            }
            pendingName = nil
            if m.2 != nil { price = -price }   // Costco "3.00-"

            if words.contains("total") && !words.contains("subtotal") { total = abs(price); continue }
            // Discount line: take it off the item above.
            if price < 0 || (lower.contains("savings") || lower.hasPrefix("/") || lower.contains("bonus buy") || lower.contains("coupon")) {
                if price < 0, var last = items.popLast() { last.price = max(0, (last.price ?? 0) + price); items.append(last) }
                continue
            }
            if skipWords.contains(where: { $0.contains(" ") ? lower.contains($0) : words.contains($0) }) { continue }

            let raw = line.replacing(priceAtEnd, with: "")
            guard raw.rangeOfCharacter(from: .letters) != nil else { continue }
            let qty = line.firstMatch(of: /(\d+)\s*@/).flatMap { Double($0.1) } ?? 1
            add(raw.replacing(/(\d+)\s*@\s*\$?\d+\.\d{2}/, with: ""), price: price, qty: qty)
        }
        return ParsedScan(store: store, total: total > 0 ? total : nil, items: items)
    }
}
