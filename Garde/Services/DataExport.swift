import Foundation
import SwiftData

/// Plain-JSON backup of everything (no photos), so the data is readable and
/// editable by any person or AI, and can be imported back.
struct KitchenExport: Codable {
    struct Item: Codable {
        var name, category, location, unit: String
        var quantity: Double
        var purchaseDate: Date
        var expirationDate: Date?
        var expirationIsEstimated: Bool
        var price: Double?
        var store: String?
        var notes: String
        var isUsedUp: Bool
        var openedDate: Date?
        var unopenedExpiration: Date?
        var unopenedExpirationIsEstimated: Bool?
        var unopenedLocationRaw: String?
        var didRestockExpired: Bool?
        var didRestockUsedUp: Bool?
        var wasTossed: Bool?
        var isLeftover: Bool?
        var usedUpDate: Date?
        var frozenDate: Date?
        var id: UUID?
        var stock: PantrySnapshot?
        var lastCheckedDate: Date?
        var barcode: String?
    }
    struct ReceiptRow: Codable { var store: String; var date: Date; var total: Double?; var rawText: String }
    struct SpiceRow: Codable { var name, level, shelfSpot: String; var purchaseDate: Date; var isWholeSpice: Bool }
    struct RecipeRow: Codable { var title, summary: String; var minutes, servings: Int; var ingredients, steps: [String]; var isFavorite: Bool }
    struct ProfileRow: Codable { var allergies, dislikes, loves: [String]; var dietNotes: String; var householdSize: Int; var skillLevel: String; var expirationWarningDays: Int }

    struct ShoppingRow: Codable {
        var name, category, quantityNote, reason: String
        var isChecked: Bool
        var sourceItemID: UUID?
        var isSpecificProduct: Bool?
        var wasAutoChecked: Bool?
        var planDemandKey: String?
        var planSourcesKey: String?
        var mealNote: String?
        var isDismissed: Bool?
    }
    struct EventRow: Codable {
        var id, itemID: UUID
        var date: Date
        var action, explanation: String
        var before, after: Data?
        var undone: Bool
        var operationID: UUID?
    }
    struct MemoryRow: Codable {
        var weeknightMinutes: Int
        var spicePreference, leftoverPreference: String
        var preferredBrands, householdMemory, ignoredFeedbackIDs: [String]
        var preferredStore: String
        var allowExtraStore: Bool
        var minimumExtraStoreSavings: Double
    }
    struct PlanRow: Codable { var day: Date; var title, summary: String; var minutes, servings: Int; var ingredients, steps, needToBuy: [String]; var isCooked: Bool; var id: UUID? }
    struct CookRow: Codable { var title: String; var date: Date; var rating: Int; var wouldChange: String; var neverAgain: Bool; var cost: Double?; var id: UUID? }
    struct BottleRow: Codable {
        var name, kind, vintage, region, notes: String
        var count: Int
        var style, format: String?
    }
    struct TakeoutRow: Codable { var restaurant, cuisine, service: String; var date: Date; var dishes: [String]; var total: Double?; var sourceID: String? }

    var format = "garde/v3"
    var events: [EventRow]?
    var memory: MemoryRow?
    var exportedAt = Date()
    var items: [Item]
    var receipts: [ReceiptRow]
    var spices: [SpiceRow]
    var recipes: [RecipeRow]
    var profile: ProfileRow?
    var shopping: [ShoppingRow]? = []
    var mealPlan: [PlanRow]? = []
    var cookLog: [CookRow]? = []
    var bar: [BottleRow]? = []
    var takeout: [TakeoutRow]? = []
    var recipeNotes: [String: String]? = [:]      // recipe title → your notes
    var monthlyBudget: Double? = nil
}

enum DataExport {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601; return e
    }()
    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    @MainActor
    static func exportJSON(context: ModelContext) throws -> URL {
        let items = try context.fetch(FetchDescriptor<PantryItem>())
        let receipts = try context.fetch(FetchDescriptor<Receipt>())
        let spices = try context.fetch(FetchDescriptor<Spice>())
        let recipes = try context.fetch(FetchDescriptor<SavedRecipe>())
        let profile = try context.fetch(FetchDescriptor<KitchenProfile>()).first

        var export = KitchenExport(
            items: items.map { .init(name: $0.name, category: $0.categoryRaw, location: $0.locationRaw, unit: $0.unit,
                                     quantity: $0.quantity, purchaseDate: $0.purchaseDate, expirationDate: $0.expirationDate,
                                     expirationIsEstimated: $0.expirationIsEstimated, price: $0.price, store: $0.store,
                                     notes: $0.notes, isUsedUp: $0.isUsedUp, openedDate: $0.openedDate,
                                     unopenedExpiration: $0.unopenedExpiration, unopenedExpirationIsEstimated: $0.unopenedExpirationIsEstimated,
                                     unopenedLocationRaw: $0.unopenedLocationRaw, didRestockExpired: $0.didRestockExpired,
                                     didRestockUsedUp: $0.didRestockUsedUp, wasTossed: $0.wasTossed, isLeftover: $0.isLeftover,
                                     usedUpDate: $0.usedUpDate, frozenDate: $0.frozenDate, id: $0.id, stock: PantrySnapshot($0), lastCheckedDate: $0.lastCheckedDate, barcode: $0.barcode) },
            receipts: receipts.map { .init(store: $0.store, date: $0.date, total: $0.total, rawText: $0.rawText) },
            spices: spices.map { .init(name: $0.name, level: $0.levelRaw, shelfSpot: $0.shelfSpot, purchaseDate: $0.purchaseDate, isWholeSpice: $0.isWholeSpice) },
            recipes: recipes.map { .init(title: $0.title, summary: $0.summary, minutes: $0.minutes, servings: $0.servings,
                                         ingredients: $0.ingredients, steps: $0.steps, isFavorite: $0.isFavorite) },
            profile: profile.map { .init(allergies: $0.allergies, dislikes: $0.dislikes, loves: $0.loves, dietNotes: $0.dietNotes,
                                         householdSize: $0.householdSize, skillLevel: $0.skillLevel, expirationWarningDays: $0.expirationWarningDays) })

        export.shopping = try context.fetch(FetchDescriptor<ShoppingItem>()).map { .init(name: $0.name, category: $0.categoryRaw, quantityNote: $0.quantityNote, reason: $0.reason, isChecked: $0.isChecked,
            sourceItemID: $0.sourceItemID, isSpecificProduct: $0.isSpecificProduct, wasAutoChecked: $0.wasAutoChecked,
            planDemandKey: $0.planDemandKey, planSourcesKey: $0.planSourcesKey, mealNote: $0.mealNote, isDismissed: $0.isDismissed) }
        export.mealPlan = try context.fetch(FetchDescriptor<MealPlanEntry>()).map { .init(day: $0.day, title: $0.title, summary: $0.summary, minutes: $0.minutes, servings: $0.servings, ingredients: $0.ingredients, steps: $0.steps, needToBuy: $0.needToBuy, isCooked: $0.isCooked, id: $0.id) }
        export.cookLog = try context.fetch(FetchDescriptor<CookLog>()).map { .init(title: $0.title, date: $0.date, rating: $0.rating, wouldChange: $0.wouldChange, neverAgain: $0.neverAgain, cost: $0.cost, id: $0.id) }
        export.takeout = try context.fetch(FetchDescriptor<TakeoutOrder>()).map { .init(restaurant: $0.restaurant, cuisine: $0.cuisine, service: $0.service, date: $0.date, dishes: $0.dishes, total: $0.total, sourceID: $0.sourceID) }
        export.recipeNotes = Dictionary(recipes.filter { !$0.notes.isEmpty }.map { ($0.title, $0.notes) }, uniquingKeysWith: { a, _ in a })
        export.monthlyBudget = profile?.monthlyBudget
        export.bar = try context.fetch(FetchDescriptor<BarBottle>()).map { .init(name: $0.name, kind: $0.kindRaw, vintage: $0.vintage, region: $0.region, notes: $0.notes, count: $0.count, style: $0.style, format: $0.format) }

        export.events = try context.fetch(FetchDescriptor<KitchenEvent>()).map {
            .init(id: $0.id, itemID: $0.itemID, date: $0.date, action: $0.action, explanation: $0.explanation,
                  before: $0.before, after: $0.after, undone: $0.undone, operationID: $0.operationID)
        }
        if let profile {
            export.memory = .init(weeknightMinutes: profile.weeknightMinutes, spicePreference: profile.spicePreference,
                                  leftoverPreference: profile.leftoverPreference, preferredBrands: profile.preferredBrands,
                                  householdMemory: profile.householdMemory, ignoredFeedbackIDs: profile.ignoredFeedbackIDs,
                                  preferredStore: profile.preferredStore, allowExtraStore: profile.allowExtraStore,
                                  minimumExtraStoreSavings: profile.minimumExtraStoreSavings)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("garde-\(Date.now.formatted(.iso8601.year().month().day())).json")
        try encoder.encode(export).write(to: url)
        return url
    }

    /// Adds everything from a backup file (does not delete existing data).
    @MainActor
    static func importJSON(from url: URL, context: ModelContext) throws -> Int {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try decoder.decode(KitchenExport.self, from: Data(contentsOf: url))
        let existingIDs = Set(try context.fetch(FetchDescriptor<PantryItem>()).map(\.id))
        for i in data.items {
            if let id = i.id, existingIDs.contains(id) { continue }
            let item = PantryItem(name: i.name, category: FoodCategory(rawValue: i.category) ?? .other,
                                  location: StorageLocation(rawValue: i.location) ?? .fridge, quantity: i.quantity, unit: i.unit,
                                  purchaseDate: i.purchaseDate, expirationDate: i.expirationDate,
                                  expirationIsEstimated: i.expirationIsEstimated, price: i.price, store: i.store)
            item.notes = i.notes; item.isUsedUp = i.isUsedUp
            item.openedDate = i.openedDate
            item.unopenedExpiration = i.unopenedExpiration
            item.unopenedExpirationIsEstimated = i.unopenedExpirationIsEstimated
            item.unopenedLocationRaw = i.unopenedLocationRaw
            item.didRestockExpired = i.didRestockExpired ?? false
            item.didRestockUsedUp = i.didRestockUsedUp ?? false
            item.wasTossed = i.wasTossed ?? false
            item.isLeftover = i.isLeftover ?? false
            item.usedUpDate = i.usedUpDate
            item.frozenDate = i.frozenDate
            if let id = i.id { item.id = id }
            i.stock?.apply(to: item)
            item.lastCheckedDate = i.lastCheckedDate; item.barcode = i.barcode
            context.insert(item)
        }
        let eventIDs = Set(try context.fetch(FetchDescriptor<KitchenEvent>()).map(\.id))
        for row in data.events ?? [] where !eventIDs.contains(row.id) {
            guard let after = row.after, let snapshot = try? JSONDecoder().decode(PantrySnapshot.self, from: after) else { continue }
            let event = KitchenEvent(itemID: row.itemID, action: row.action, explanation: row.explanation,
                                     before: nil, after: snapshot, operationID: row.operationID)
            event.id = row.id; event.date = row.date; event.before = row.before; event.undone = row.undone
            context.insert(event)
        }
        for r in data.receipts { context.insert(Receipt(store: r.store, date: r.date, total: r.total, rawText: r.rawText)) }
        for s in data.spices {
            context.insert(Spice(name: s.name, level: SpiceLevel(rawValue: s.level) ?? .full, purchaseDate: s.purchaseDate,
                                 shelfSpot: s.shelfSpot, isWholeSpice: s.isWholeSpice))
        }
        for r in data.recipes {
            let saved = SavedRecipe(title: r.title, summary: r.summary, minutes: r.minutes, servings: r.servings, ingredients: r.ingredients, steps: r.steps)
            saved.isFavorite = r.isFavorite
            saved.notes = data.recipeNotes?[r.title] ?? ""
            context.insert(saved)
        }
        for r in data.shopping ?? [] {
            let i = ShoppingItem(name: r.name, category: FoodCategory(rawValue: r.category) ?? .other, quantityNote: r.quantityNote, reason: r.reason)
            i.isChecked = r.isChecked
            i.sourceItemID = r.sourceItemID; i.isSpecificProduct = r.isSpecificProduct ?? false; i.wasAutoChecked = r.wasAutoChecked ?? false
            i.planDemandKey = r.planDemandKey ?? ""; i.planSourcesKey = r.planSourcesKey ?? ""; i.mealNote = r.mealNote ?? ""; i.isDismissed = r.isDismissed ?? false
            context.insert(i)
        }
        for r in data.mealPlan ?? [] {
            let e = MealPlanEntry(day: r.day, title: r.title, summary: r.summary, minutes: r.minutes, servings: r.servings, ingredients: r.ingredients, steps: r.steps, needToBuy: r.needToBuy)
            e.isCooked = r.isCooked; if let id = r.id { e.id = id }; context.insert(e)
        }
        for r in data.cookLog ?? [] {
            let l = CookLog(title: r.title, rating: r.rating, wouldChange: r.wouldChange, neverAgain: r.neverAgain, cost: r.cost)
            l.date = r.date; if let id = r.id { l.id = id }; context.insert(l)
        }
        for r in data.bar ?? [] {
            let b = BarBottle(name: r.name, kind: BottleKind(rawValue: r.kind) ?? .other, vintage: r.vintage, region: r.region, count: r.count)
            b.notes = r.notes; b.style = r.style ?? ""; b.format = r.format ?? ""
            context.insert(b)
        }
        for r in data.takeout ?? [] {
            let o = TakeoutOrder(restaurant: r.restaurant, cuisine: r.cuisine, date: r.date, dishes: r.dishes, total: r.total, service: r.service)
            o.sourceID = r.sourceID
            context.insert(o)
        }
        if let p = data.profile {
            let existing = try context.fetch(FetchDescriptor<KitchenProfile>()).first ?? { let n = KitchenProfile(); context.insert(n); return n }()
            existing.allergies = Array(Set(existing.allergies + p.allergies)).sorted()
            existing.dislikes = Array(Set(existing.dislikes + p.dislikes)).sorted()
            existing.loves = Array(Set(existing.loves + p.loves)).sorted()
            if existing.dietNotes.isEmpty { existing.dietNotes = p.dietNotes }
            if existing.monthlyBudget == 0, let b = data.monthlyBudget { existing.monthlyBudget = b }
            if let memory = data.memory {
                existing.weeknightMinutes = memory.weeknightMinutes; existing.spicePreference = memory.spicePreference
                existing.leftoverPreference = memory.leftoverPreference; existing.preferredBrands = memory.preferredBrands
                existing.householdMemory = memory.householdMemory; existing.ignoredFeedbackIDs = memory.ignoredFeedbackIDs
                existing.preferredStore = memory.preferredStore; existing.allowExtraStore = memory.allowExtraStore
                existing.minimumExtraStoreSavings = memory.minimumExtraStoreSavings
            }
        }
        try context.save()
        return data.items.count + data.spices.count + data.receipts.count + data.recipes.count
    }
}
