import Foundation
import SwiftData

// MARK: - Enums

enum StorageLocation: String, Codable, CaseIterable, Identifiable {
    case fridge, freezer, pantry, counter
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .fridge: "refrigerator"
        case .freezer: "snowflake"
        case .pantry: "cabinet"
        case .counter: "basket"
        }
    }
}

enum FoodCategory: String, Codable, CaseIterable, Identifiable {
    case meat, seafood, poultry, dairy, cheese, eggs, produce, fruit, bakery,
         grains, canned, condiments, frozen, beverages, snacks, deli, other
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum SpiceLevel: String, Codable, CaseIterable, Identifiable {
    case full, half, low, empty
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

// MARK: - Pantry item

@Model
final class PantryItem {
    var id: UUID = UUID()
    var name: String = ""
    var categoryRaw: String = FoodCategory.other.rawValue
    var locationRaw: String = StorageLocation.fridge.rawValue
    var quantity: Double = 1
    var unit: String = "each"
    var purchaseDate: Date = Date()
    var expirationDate: Date?
    var expirationIsEstimated: Bool = true
    var price: Double?
    var store: String?
    var notes: String = ""
    @Attribute(.externalStorage) var photo: Data?
    var isUsedUp: Bool = false
    var receipt: Receipt?

    init(name: String,
         category: FoodCategory = .other,
         location: StorageLocation = .fridge,
         quantity: Double = 1,
         unit: String = "each",
         purchaseDate: Date = Date(),
         expirationDate: Date? = nil,
         expirationIsEstimated: Bool = true,
         price: Double? = nil,
         store: String? = nil) {
        self.name = name
        self.categoryRaw = category.rawValue
        self.locationRaw = location.rawValue
        self.quantity = quantity
        self.unit = unit
        self.purchaseDate = purchaseDate
        self.expirationDate = expirationDate
        self.expirationIsEstimated = expirationIsEstimated
        self.price = price
        self.store = store
    }

    var category: FoodCategory {
        get { FoodCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
    var location: StorageLocation {
        get { StorageLocation(rawValue: locationRaw) ?? .fridge }
        set { locationRaw = newValue.rawValue }
    }

    /// Whole days until expiration (negative = expired). nil if unknown.
    var daysLeft: Int? {
        guard let exp = expirationDate else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: exp)).day
    }
}

// MARK: - Receipt

@Model
final class Receipt {
    var id: UUID = UUID()
    var store: String = ""
    var date: Date = Date()
    var total: Double?
    var rawText: String = ""
    @Attribute(.externalStorage) var image: Data?
    @Relationship(deleteRule: .nullify, inverse: \PantryItem.receipt) var items: [PantryItem] = []

    init(store: String, date: Date = Date(), total: Double? = nil, rawText: String = "", image: Data? = nil) {
        self.store = store
        self.date = date
        self.total = total
        self.rawText = rawText
        self.image = image
    }
}

// MARK: - Spice

@Model
final class Spice {
    var id: UUID = UUID()
    var name: String = ""
    var levelRaw: String = SpiceLevel.full.rawValue
    var purchaseDate: Date = Date()
    var shelfSpot: String = ""   // e.g. "Rack 2, top row"
    var isWholeSpice: Bool = false

    init(name: String, level: SpiceLevel = .full, purchaseDate: Date = Date(), shelfSpot: String = "", isWholeSpice: Bool = false) {
        self.name = name
        self.levelRaw = level.rawValue
        self.purchaseDate = purchaseDate
        self.shelfSpot = shelfSpot
        self.isWholeSpice = isWholeSpice
    }

    var level: SpiceLevel {
        get { SpiceLevel(rawValue: levelRaw) ?? .full }
        set { levelRaw = newValue.rawValue }
    }

    /// Ground spices lose punch after ~2 years, whole after ~3–4.
    var bestBy: Date {
        Calendar.current.date(byAdding: .month, value: isWholeSpice ? 42 : 24, to: purchaseDate) ?? purchaseDate
    }
    var isStale: Bool { bestBy < .now }
}

// MARK: - Saved recipe

@Model
final class SavedRecipe {
    var id: UUID = UUID()
    var title: String = ""
    var summary: String = ""
    var minutes: Int = 0
    var servings: Int = 2
    var ingredients: [String] = []
    var steps: [String] = []
    var createdAt: Date = Date()
    var isFavorite: Bool = false

    init(title: String, summary: String, minutes: Int, servings: Int, ingredients: [String], steps: [String]) {
        self.title = title
        self.summary = summary
        self.minutes = minutes
        self.servings = servings
        self.ingredients = ingredients
        self.steps = steps
    }
}

// MARK: - Profile (single row)

@Model
final class KitchenProfile {
    var allergies: [String] = []        // HARD rule: never suggested
    var dislikes: [String] = []         // soft: avoid
    var loves: [String] = []            // soft: lean toward
    var dietNotes: String = ""          // free text, e.g. "no seed oils"
    var householdSize: Int = 1
    var skillLevel: String = "Confident home cook"
    var expirationWarningDays: Int = 2

    init() {}
}
