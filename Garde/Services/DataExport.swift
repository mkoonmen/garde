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
    }
    struct ReceiptRow: Codable { var store: String; var date: Date; var total: Double?; var rawText: String }
    struct SpiceRow: Codable { var name, level, shelfSpot: String; var purchaseDate: Date; var isWholeSpice: Bool }
    struct RecipeRow: Codable { var title, summary: String; var minutes, servings: Int; var ingredients, steps: [String]; var isFavorite: Bool }
    struct ProfileRow: Codable { var allergies, dislikes, loves: [String]; var dietNotes: String; var householdSize: Int; var skillLevel: String; var expirationWarningDays: Int }

    var format = "garde/v1"
    var exportedAt = Date()
    var items: [Item]
    var receipts: [ReceiptRow]
    var spices: [SpiceRow]
    var recipes: [RecipeRow]
    var profile: ProfileRow?
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

        let export = KitchenExport(
            items: items.map { .init(name: $0.name, category: $0.categoryRaw, location: $0.locationRaw, unit: $0.unit,
                                     quantity: $0.quantity, purchaseDate: $0.purchaseDate, expirationDate: $0.expirationDate,
                                     expirationIsEstimated: $0.expirationIsEstimated, price: $0.price, store: $0.store,
                                     notes: $0.notes, isUsedUp: $0.isUsedUp) },
            receipts: receipts.map { .init(store: $0.store, date: $0.date, total: $0.total, rawText: $0.rawText) },
            spices: spices.map { .init(name: $0.name, level: $0.levelRaw, shelfSpot: $0.shelfSpot, purchaseDate: $0.purchaseDate, isWholeSpice: $0.isWholeSpice) },
            recipes: recipes.map { .init(title: $0.title, summary: $0.summary, minutes: $0.minutes, servings: $0.servings,
                                         ingredients: $0.ingredients, steps: $0.steps, isFavorite: $0.isFavorite) },
            profile: profile.map { .init(allergies: $0.allergies, dislikes: $0.dislikes, loves: $0.loves, dietNotes: $0.dietNotes,
                                         householdSize: $0.householdSize, skillLevel: $0.skillLevel, expirationWarningDays: $0.expirationWarningDays) })

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
        for i in data.items {
            let item = PantryItem(name: i.name, category: FoodCategory(rawValue: i.category) ?? .other,
                                  location: StorageLocation(rawValue: i.location) ?? .fridge, quantity: i.quantity, unit: i.unit,
                                  purchaseDate: i.purchaseDate, expirationDate: i.expirationDate,
                                  expirationIsEstimated: i.expirationIsEstimated, price: i.price, store: i.store)
            item.notes = i.notes; item.isUsedUp = i.isUsedUp
            context.insert(item)
        }
        for r in data.receipts { context.insert(Receipt(store: r.store, date: r.date, total: r.total, rawText: r.rawText)) }
        for s in data.spices {
            context.insert(Spice(name: s.name, level: SpiceLevel(rawValue: s.level) ?? .full, purchaseDate: s.purchaseDate,
                                 shelfSpot: s.shelfSpot, isWholeSpice: s.isWholeSpice))
        }
        for r in data.recipes {
            let saved = SavedRecipe(title: r.title, summary: r.summary, minutes: r.minutes, servings: r.servings, ingredients: r.ingredients, steps: r.steps)
            saved.isFavorite = r.isFavorite
            context.insert(saved)
        }
        if let p = data.profile {
            let existing = try context.fetch(FetchDescriptor<KitchenProfile>()).first ?? { let n = KitchenProfile(); context.insert(n); return n }()
            existing.allergies = Array(Set(existing.allergies + p.allergies)).sorted()
            existing.dislikes = Array(Set(existing.dislikes + p.dislikes)).sorted()
            existing.loves = Array(Set(existing.loves + p.loves)).sorted()
            if existing.dietNotes.isEmpty { existing.dietNotes = p.dietNotes }
        }
        try context.save()
        return data.items.count + data.spices.count + data.receipts.count + data.recipes.count
    }
}
