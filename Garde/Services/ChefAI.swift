import Foundation
import FoundationModels

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
                       category: FoodCategory(rawValue: $0.category.lowercased()) ?? .other,
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
        let session = LanguageModelSession(instructions: """
        You read grocery receipts, food labels and photos of food, and extract the food items.
        Receipts use cryptic abbreviations; expand them to normal names (e.g. 'BNLS SKNLS CHKN THGH' -> 'Boneless skinless chicken thighs').
        Never invent items that are not in the text or labels.
        """)
        let prompt = """
        Today is \(Date.now.formatted(date: .numeric, time: .omitted)).
        Text read from the photo:
        \(text.isEmpty ? "(no text)" : String(text.prefix(4000)))

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
    }

    /// Generates recipes from what's in the kitchen, prioritizing what expires first.
    /// Any recipe that mentions an allergen is discarded by `AllergenGuard`.
    func suggestRecipes(items: [PantryItem], spices: [Spice], profile: KitchenProfile, request: RecipeRequest) async throws -> (recipes: [RecipeIdea], blocked: Int) {
        guard state == .available else { return ([], 0) }

        let active = items.filter { !$0.isUsedUp }
            .sorted { ($0.daysLeft ?? 999) < ($1.daysLeft ?? 999) }
        let inventory = active.prefix(60).map { item -> String in
            let d = item.daysLeft.map { $0 < 0 ? "EXPIRED" : "\($0)d left" } ?? "no date"
            return "- \(item.name) (\(formatQty(item.quantity)) \(item.unit), \(item.location.label), \(d))"
        }.joined(separator: "\n")
        let spiceList = spices.filter { $0.level != .empty }.map(\.name).joined(separator: ", ")

        let session = LanguageModelSession(instructions: """
        You are a private chef cooking for one household from what they already have.
        ABSOLUTE RULE: never include these allergens or anything made from them: \(profile.allergies.isEmpty ? "none" : profile.allergies.joined(separator: ", ")).
        Avoid: \(profile.dislikes.joined(separator: ", ").ifEmpty("nothing")).
        They love: \(profile.loves.joined(separator: ", ").ifEmpty("anything good")).
        Diet notes: \(profile.dietNotes.ifEmpty("none")).
        Cooking level: \(profile.skillLevel). Default servings: \(profile.householdSize).
        Prefer ingredients that expire soonest. Assume salt, pepper, oil and water are available.
        Do not use EXPIRED items.
        """)

        let prompt = """
        Kitchen inventory (soonest-expiring first):
        \(inventory.ifEmpty("(empty)"))

        Spices on hand: \(spiceList.ifEmpty("basic only"))

        \(request.mustUse.isEmpty ? "" : "Must use: \(request.mustUse.joined(separator: ", "))")
        Mood: \(request.mood.ifEmpty("chef's choice"))
        Max time: \(request.maxMinutes) minutes.
        Suggest 3 different dishes.
        """

        let batch = try await session.respond(to: prompt, generating: RecipeBatch.self).content
        let safe = batch.recipes.filter {
            AllergenGuard.violations(in: [$0.title] + $0.ingredients + $0.steps, allergies: profile.allergies).isEmpty
        }
        return (safe, batch.recipes.count - safe.count)
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
enum HeuristicParser {
    static func parse(_ text: String) -> ParsedScan {
        let skip = ["total", "subtotal", "tax", "change", "cash", "visa", "mastercard", "amex", "debit", "credit",
                    "balance", "savings", "coupon", "bag", "thank", "card", "auth", "member", "points", "approved"]
        var items: [ParsedItem] = []
        var total = 0.0
        let priceRegex = /(\d+\.\d{2})\s*[A-Z]?\s*$/
        let lines = text.split(separator: "\n").map(String.init)
        for line in lines {
            let lower = line.lowercased()
            guard let m = line.firstMatch(of: priceRegex), let price = Double(m.1) else { continue }
            if lower.contains("total") && !lower.contains("sub") { total = price; continue }
            if skip.contains(where: lower.contains) { continue }
            let name = line.replacing(priceRegex, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard name.count >= 3, name.rangeOfCharacter(from: .letters) != nil else { continue }
            items.append(ParsedItem(name: name.capitalized, category: .other, quantity: 1, unit: "each",
                                    price: price, printedExpiration: nil))
        }
        let store = lines.first(where: { $0.rangeOfCharacter(from: .letters) != nil })?.capitalized ?? ""
        return ParsedScan(store: store, total: total > 0 ? total : nil, items: items)
    }
}
