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
    var usedUpDate: Date?
    var wasTossed: Bool = false        // true = thrown out (waste), false = eaten
    var isLeftover: Bool = false
    var openedDate: Date?
    var frozenDate: Date?
    var barcode: String?
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

    /// Can this go in the freezer? (false for things like eggs-in-shell, lettuce, canned goods)
    var canFreeze: Bool {
        guard location != .freezer else { return false }
        if let r = ShelfLife.rule(for: name) { return r.freezer != nil }
        return ![.produce, .canned, .grains, .snacks, .beverages, .condiments].contains(category)
    }

    /// Moves it to the freezer and restarts the clock with freezer shelf life.
    func freeze() {
        frozenDate = .now
        location = .freezer
        expirationDate = ShelfLife.estimatedExpiration(name: name, category: category, in: .freezer)
        expirationIsEstimated = true
    }

    /// Thawed in the fridge: cook within a couple of days.
    func thaw() {
        location = .fridge
        frozenDate = nil
        let days = (category == .seafood || category == .poultry || category == .meat) ? 2 : 3
        expirationDate = Calendar.current.date(byAdding: .day, value: days, to: .now)
        expirationIsEstimated = true
    }

    func markUsed(tossed: Bool = false) {
        isUsedUp = true
        wasTossed = tossed
        usedUpDate = .now
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
    @Relationship(deleteRule: .nullify, inverse: \PantryItem.receipt) var items: [PantryItem]? = []   // optional for iCloud sync

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
    var timesCooked: Int = 0

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

// MARK: - Shopping list

@Model
final class ShoppingItem {
    var id: UUID = UUID()
    var name: String = ""
    var categoryRaw: String = FoodCategory.other.rawValue
    var quantityNote: String = ""
    var isChecked: Bool = false
    var reason: String = ""          // "Running low", "For Tue: Chicken piccata", "Added by you"
    var createdAt: Date = Date()

    init(name: String, category: FoodCategory = .other, quantityNote: String = "", reason: String = "Added by you") {
        self.name = name
        self.categoryRaw = category.rawValue
        self.quantityNote = quantityNote
        self.reason = reason
    }
    var category: FoodCategory {
        get { FoodCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
}

// MARK: - Meal plan

@Model
final class MealPlanEntry {
    var id: UUID = UUID()
    var day: Date = Date()           // start of day
    var title: String = ""
    var summary: String = ""
    var minutes: Int = 0
    var servings: Int = 2
    var ingredients: [String] = []
    var steps: [String] = []
    var needToBuy: [String] = []
    var isCooked: Bool = false

    init(day: Date, title: String, summary: String, minutes: Int, servings: Int, ingredients: [String], steps: [String], needToBuy: [String]) {
        self.day = Calendar.current.startOfDay(for: day)
        self.title = title
        self.summary = summary
        self.minutes = minutes
        self.servings = servings
        self.ingredients = ingredients
        self.steps = steps
        self.needToBuy = needToBuy
    }
}

// MARK: - Taste memory

@Model
final class CookLog {
    var id: UUID = UUID()
    var title: String = ""
    var date: Date = Date()
    var rating: Int = 0              // 1–5
    var wouldChange: String = ""
    var neverAgain: Bool = false
    var cost: Double?

    init(title: String, rating: Int, wouldChange: String = "", neverAgain: Bool = false, cost: Double? = nil) {
        self.title = title
        self.rating = rating
        self.wouldChange = wouldChange
        self.neverAgain = neverAgain
        self.cost = cost
    }
}

// MARK: - Bar & cellar

enum BottleKind: String, Codable, CaseIterable, Identifiable {
    case red, white, rose, sparkling, dessert, bourbon, whiskey, tequila, rum, gin, vodka, other
    var id: String { rawValue }
    var label: String { self == .rose ? "Rosé" : rawValue.capitalized }
}

@Model
final class BarBottle {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = BottleKind.red.rawValue
    var vintage: String = ""
    var region: String = ""
    var count: Int = 1
    var notes: String = ""
    @Attribute(.externalStorage) var photo: Data?

    init(name: String, kind: BottleKind, vintage: String = "", region: String = "", count: Int = 1) {
        self.name = name
        self.kindRaw = kind.rawValue
        self.vintage = vintage
        self.region = region
        self.count = count
    }
    var kind: BottleKind {
        get { BottleKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }
}

// MARK: - Shared container (app + widget + Siri)

enum GardeStore {
    static let appGroup = "group.com.michaelkoonmen.garde"
    static let schema = Schema([PantryItem.self, Receipt.self, Spice.self, SavedRecipe.self, KitchenProfile.self,
                                ShoppingItem.self, MealPlanEntry.self, CookLog.self, BarBottle.self])

    static let cloudContainer = "iCloud.com.michaelkoonmen.garde"

    /// The app syncs through the user's private iCloud database (when iCloud sync is on); the widget only reads locally.
    static var syncEnabled: Bool {
        UserDefaults(suiteName: appGroup)?.object(forKey: "icloudSync") as? Bool ?? true
    }

    static let container: ModelContainer = makeContainer(cloud: syncEnabled && !isExtension)
    static var isExtension: Bool { Bundle.main.bundlePath.hasSuffix(".appex") }

    static func makeContainer(cloud: Bool) -> ModelContainer {
        if cloud {
            let synced = ModelConfiguration(schema: schema, groupContainer: .identifier(appGroup),
                                            cloudKitDatabase: .private(cloudContainer))
            if let c = try? ModelContainer(for: schema, configurations: synced) { return c }
        }
        let config = ModelConfiguration(schema: schema, groupContainer: .identifier(appGroup), cloudKitDatabase: .none)
        if let c = try? ModelContainer(for: schema, configurations: config) { return c }
        // Fallback if the App Group isn't provisioned yet: app-only storage.
        if let c = try? ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .none)) { return c }
        // Last resort so the app still opens (data won't persist this launch).
        print("Garde: persistent store unavailable, using in-memory store")
        return try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }
}
