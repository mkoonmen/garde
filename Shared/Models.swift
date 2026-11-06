import Foundation
import SwiftData
import UserNotifications

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
         grains, canned, condiments, frozen, beverages, snacks, deli, other,
         sweets, candy, coffee, baking
    var id: String { rawValue }
    var label: String {
        switch self {
        case .sweets: "Desserts & sweets"
        case .coffee: "Coffee & tea"
        default: rawValue.capitalized
        }
    }
    var symbol: String {
        switch self {
        case .meat: "fork.knife"; case .seafood: "fish"; case .poultry: "bird"; case .dairy: "drop"
        case .cheese: "triangle.lefthalf.filled"; case .eggs: "oval.portrait"; case .produce: "carrot"; case .fruit: "apple.logo"
        case .bakery: "birthday.cake"; case .grains: "takeoutbag.and.cup.and.straw"; case .canned: "cylinder"; case .condiments: "flask"
        case .frozen: "snowflake"; case .beverages: "waterbottle"; case .snacks: "popcorn"; case .deli: "rectangle.stack"
        case .sweets: "birthday.cake.fill"; case .candy: "heart.circle"; case .coffee: "cup.and.saucer"; case .baking: "frying.pan"
        case .other: "square.grid.2x2"
        }
    }
}

enum SpiceLevel: String, Codable, CaseIterable, Identifiable {
    case full, half, low, empty
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

// MARK: - Pantry item

/// A value copy lets the editor preview opening and undoing without changing the stored item until Save.
struct PantryStorage {
    var location: StorageLocation = .fridge
    var expirationDate: Date?
    var expirationIsEstimated = true
    var openedDate: Date?
    var unopenedExpiration: Date?
    var unopenedExpirationIsEstimated: Bool?
    var unopenedLocation: StorageLocation?

    mutating func open(name: String, category: FoodCategory, on date: Date) {
        guard openedDate == nil else { return }
        unopenedExpiration = expirationDate
        unopenedExpirationIsEstimated = expirationIsEstimated
        unopenedLocation = location
        openedDate = date
        if location != .freezer && ShelfLife.needsFridgeAfterOpening(name: name, category: category) { location = .fridge }
        let shortened = ShelfLife.openedExpiration(name: name, category: category, current: expirationDate, openedOn: date)
        if shortened != expirationDate {
            expirationDate = shortened
            expirationIsEstimated = true
        }
    }

    mutating func unopen() {
        guard openedDate != nil else { return }
        openedDate = nil
        if let unopenedExpirationIsEstimated {
            expirationIsEstimated = unopenedExpirationIsEstimated
            expirationDate = unopenedExpiration
        } else if let unopenedExpiration {
            // An older opened item may have only the sealed date. Keep its recorded date if the snapshot is missing.
            expirationDate = unopenedExpiration
        }
        if let unopenedLocation { location = unopenedLocation }
        unopenedExpiration = nil
        unopenedExpirationIsEstimated = nil
        unopenedLocation = nil
    }
}

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
    var didRestockExpired: Bool = false
    var didRestockUsedUp: Bool = false
    var isUsedUp: Bool = false
    var usedUpDate: Date?
    var wasTossed: Bool = false        // true = thrown out (waste), false = eaten
    var isLeftover: Bool = false
    var openedDate: Date?
    var unopenedExpiration: Date?      // the sealed date, kept so "not opened" can be undone
    var unopenedExpirationIsEstimated: Bool?
    var unopenedLocationRaw: String?
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

    var storage: PantryStorage {
        get {
            PantryStorage(location: location, expirationDate: expirationDate, expirationIsEstimated: expirationIsEstimated,
                         openedDate: openedDate, unopenedExpiration: unopenedExpiration,
                         unopenedExpirationIsEstimated: unopenedExpirationIsEstimated,
                         unopenedLocation: unopenedLocationRaw.flatMap(StorageLocation.init(rawValue:)))
        }
        set {
            location = newValue.location
            expirationDate = newValue.expirationDate
            expirationIsEstimated = newValue.expirationIsEstimated
            openedDate = newValue.openedDate
            unopenedExpiration = newValue.unopenedExpiration
            unopenedExpirationIsEstimated = newValue.unopenedExpirationIsEstimated
            unopenedLocationRaw = newValue.unopenedLocation?.rawValue
        }
    }

    func open(on date: Date = .now) { storage.open(name: name, category: category, on: date) }
    func unopen() { storage.unopen() }
    var isOpened: Bool { openedDate != nil }

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
        if let r = ShelfLife.rule(for: name, category: category) { return r.freezer != nil }
        return ![.produce, .canned, .grains, .snacks, .beverages, .condiments, .candy, .coffee, .baking].contains(category)
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
        if !isUsedUp { didRestockUsedUp = false }
        isUsedUp = true
        wasTossed = tossed
        usedUpDate = .now
        // Leftovers already eaten or tossed: drop tomorrow's "leftovers for lunch?" reminder.
        if isLeftover { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["leftover-" + id.uuidString]) }
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
    var sourceID: String?          // "gmail:<message id>" for imported emails (prevents duplicates, allows re-import)
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
    var notes: String = ""          // your own tweaks ("less salt, add chili flakes")

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
    var monthlyBudget: Double = 0       // grocery budget per month, 0 = off

    init() {}

    /// iCloud can briefly create a second, empty profile on a new device. Merge them so allergies are never lost:
    /// the fullest profile is kept, every list is unioned into it, the rest are deleted.
    @MainActor static func merge(context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<KitchenProfile>())) ?? []
        guard all.count > 1 else { return }
        // Choose by content only, so every synced device picks the same one (picking by fetch order could make two
        // devices each delete a different copy and lose both).
        func sig(_ p: KitchenProfile) -> String {
            [p.allergies, p.loves, p.dislikes].map { $0.map { $0.lowercased() }.sorted().joined(separator: "|") }.joined(separator: "#") + "#" + p.dietNotes
        }
        func score(_ p: KitchenProfile) -> Int { p.allergies.count * 100 + p.loves.count + p.dislikes.count + (p.dietNotes.isEmpty ? 0 : 1) }
        let ordered = all.sorted { score($0) != score($1) ? score($0) > score($1) : sig($0) < sig($1) }
        let keep = ordered[0]
        func union(_ a: [String], _ b: [String]) -> [String] { a + b.filter { x in !a.contains { $0.caseInsensitiveCompare(x) == .orderedSame } } }
        for p in ordered.dropFirst() {
            if sig(p) == sig(keep) && score(p) == score(keep) { continue }   // identical copies are harmless; deleting one risks both
            keep.allergies = union(keep.allergies, p.allergies)   // allergies always union: safer to keep one too many
            if keep.loves.isEmpty { keep.loves = p.loves }         // tastes: keep's own, so a removed dislike doesn't come back
            if keep.dislikes.isEmpty { keep.dislikes = p.dislikes }
            if keep.dietNotes.isEmpty { keep.dietNotes = p.dietNotes }
            if keep.monthlyBudget == 0 { keep.monthlyBudget = p.monthlyBudget }
            context.delete(p)
        }
        try? context.save()
    }
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

/// Top-level drink family, picked first when adding a bottle.
enum DrinkCategory: String, CaseIterable, Identifiable {
    case liquor, wine, beer, seltzer, other
    var id: String { rawValue }
    var label: String {
        switch self { case .liquor: "Liquor"; case .wine: "Wine"; case .beer: "Beer & cider"; case .seltzer: "Hard seltzer & RTD"; case .other: "Other" }
    }
    var kinds: [BottleKind] { BottleKind.allCases.filter { $0.category == self } }
}

/// The type of bottle. Raw values are stored, so old ones (red, bourbon…) never change.
enum BottleKind: String, Codable, CaseIterable, Identifiable {
    // Wine
    case red, white, rose, sparkling, dessert, orangeWine, fortified
    // Liquor
    case bourbon, rye, scotch, irish, japanese, whiskey, tequila, mezcal, rum, gin, vodka,
         cognac, brandy, liqueur, amaro, vermouth, absinthe, sake, soju, bitters
    // Beer
    case lager, pilsner, ipa, paleAle, wheat, stout, porter, amber, belgian, sour, cider, nonAlcBeer
    // Seltzer
    case seltzer, cannedCocktail
    case other
    var id: String { rawValue }

    var category: DrinkCategory {
        switch self {
        case .red, .white, .rose, .sparkling, .dessert, .orangeWine, .fortified: .wine
        case .lager, .pilsner, .ipa, .paleAle, .wheat, .stout, .porter, .amber, .belgian, .sour, .cider, .nonAlcBeer: .beer
        case .seltzer, .cannedCocktail: .seltzer
        case .other: .other
        default: .liquor
        }
    }

    var label: String {
        switch self {
        case .rose: "Rosé"
        case .orangeWine: "Orange / skin-contact"
        case .fortified: "Port, sherry & fortified"
        case .rye: "Rye whiskey"
        case .scotch: "Scotch"
        case .irish: "Irish whiskey"
        case .japanese: "Japanese whisky"
        case .whiskey: "Other whiskey"
        case .cognac: "Cognac & Armagnac"
        case .brandy: "Brandy & pisco"
        case .liqueur: "Liqueur"
        case .amaro: "Amaro & aperitivo"
        case .bitters: "Cocktail bitters"
        case .ipa: "IPA"
        case .paleAle: "Pale ale"
        case .wheat: "Wheat / hefeweizen"
        case .stout: "Stout"
        case .amber: "Amber & brown ale"
        case .belgian: "Belgian & Trappist"
        case .sour: "Sour & gose"
        case .nonAlcBeer: "Non-alcoholic beer"
        case .seltzer: "Hard seltzer"
        case .cannedCocktail: "Canned cocktail / RTD"
        default: rawValue.capitalized
        }
    }

    /// Finer styles to choose from under this type (empty = none).
    var styles: [String] {
        switch self {
        case .red: ["Cabernet Sauvignon", "Merlot", "Pinot Noir", "Syrah / Shiraz", "Malbec", "Zinfandel", "Sangiovese / Chianti", "Tempranillo / Rioja", "Grenache / Garnacha", "Nebbiolo / Barolo", "Cabernet Franc", "Petite Sirah", "Bordeaux blend", "Red blend"]
        case .white: ["Chardonnay (oaked)", "Chardonnay (unoaked)", "Sauvignon Blanc", "Pinot Grigio / Gris", "Riesling (dry)", "Riesling (sweet)", "Moscato", "Chenin Blanc", "Albariño", "Grüner Veltliner", "Gewürztraminer", "Viognier", "Vermentino", "White blend"]
        case .rose: ["Provence (dry)", "Sparkling rosé", "White Zinfandel", "Other rosé"]
        case .sparkling: ["Champagne", "Prosecco", "Cava", "Crémant", "Lambrusco", "Pét-nat", "Other sparkling"]
        case .dessert: ["Sauternes", "Ice wine", "Late harvest", "Tokaji", "Vin Santo"]
        case .fortified: ["Ruby port", "Tawny port", "Fino / Manzanilla sherry", "Amontillado / Oloroso", "Pedro Ximénez", "Madeira", "Marsala"]
        case .bourbon: ["Straight", "Small batch", "Single barrel", "Bottled-in-bond", "Wheated", "High rye", "Cask strength"]
        case .rye: ["Straight rye", "Bottled-in-bond", "Canadian rye", "Cask strength"]
        case .scotch: ["Single malt (Speyside)", "Single malt (Highland)", "Islay / peated", "Islands", "Campbeltown", "Blended", "Blended malt"]
        case .irish: ["Blended", "Single pot still", "Single malt"]
        case .japanese: ["Single malt", "Blended"]
        case .whiskey: ["American single malt", "Tennessee", "Canadian", "Corn", "Flavored"]
        case .tequila: ["Blanco / silver", "Reposado", "Añejo", "Extra añejo", "Cristalino"]
        case .mezcal: ["Espadín", "Tobalá", "Ensamble"]
        case .rum: ["White / silver", "Gold", "Dark", "Aged", "Spiced", "Overproof", "Rhum agricole", "Cachaça", "Coconut"]
        case .gin: ["London dry", "New Western / contemporary", "Old Tom", "Plymouth", "Navy strength", "Sloe gin"]
        case .vodka: ["Unflavored", "Flavored", "Citrus", "Vanilla"]
        case .cognac: ["VS", "VSOP", "XO", "Armagnac"]
        case .brandy: ["American brandy", "Spanish brandy", "Pisco", "Calvados / apple", "Grappa", "Eau de vie"]
        case .liqueur: ["Orange (triple sec, Cointreau)", "Coffee", "Cream", "Herbal", "Nut / almond", "Fruit", "Elderflower", "Maraschino", "Chocolate"]
        case .amaro: ["Aperitivo (Campari, Aperol)", "Medium amaro", "Fernet", "Chartreuse"]
        case .vermouth: ["Sweet / rosso", "Dry", "Blanc / bianco", "Lillet / aromatized wine"]
        case .sake: ["Junmai", "Ginjo", "Daiginjo", "Nigori", "Sparkling"]
        case .lager: ["American light", "Mexican lager", "Helles", "Märzen / Oktoberfest", "Vienna", "Dark lager", "Bock"]
        case .pilsner: ["German pils", "Czech pils", "Italian pils"]
        case .ipa: ["West Coast", "Hazy / New England", "Double / imperial", "Session", "Black IPA"]
        case .paleAle: ["American pale", "English bitter", "ESB", "Blonde ale", "Cream ale"]
        case .wheat: ["Hefeweizen", "Witbier", "American wheat", "Fruit wheat"]
        case .stout: ["Dry / Irish", "Milk stout", "Oatmeal", "Imperial", "Pastry stout"]
        case .porter: ["Robust", "Baltic", "Smoked"]
        case .belgian: ["Dubbel", "Tripel", "Quadrupel", "Saison", "Belgian strong"]
        case .sour: ["Gose", "Berliner weisse", "Fruited sour", "Lambic / gueuze", "Flanders red"]
        case .cider: ["Dry", "Semi-sweet", "Rosé cider", "Perry (pear)"]
        case .seltzer: ["Lime", "Black cherry", "Mango", "Variety pack", "Tequila seltzer", "Vodka seltzer"]
        case .cannedCocktail: ["Margarita", "Vodka soda", "Gin & tonic", "Paloma", "Mule", "Old fashioned", "Spritz"]
        default: []
        }
    }

    /// Bottle / can / keg choices make sense for beer, cider and seltzer.
    var hasFormat: Bool { category == .beer || category == .seltzer }
    static let formats = ["Bottle", "Can", "Tallboy can", "Draft / keg", "Growler", "Crowler"]
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
    var style: String = ""
    var format: String = ""
    @Attribute(.externalStorage) var photo: Data?

    init(name: String, kind: BottleKind, vintage: String = "", region: String = "", count: Int = 1) {
        self.name = name
        self.kindRaw = kind.rawValue
        self.vintage = vintage
        self.region = region
        self.count = count
    }
    /// "Pinot Noir (Red)" style description for the chef.
    var typeLabel: String { style.isEmpty ? kind.label : "\(style) \(kind.label.lowercased())" }
    var kind: BottleKind {
        get { BottleKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }
}

// MARK: - Takeout (DoorDash, Uber Eats, Grubhub… receipts from Gmail)

@Model
final class TakeoutOrder {
    var id: UUID = UUID()
    var restaurant: String = ""
    var cuisine: String = ""
    var date: Date = Date()
    var dishes: [String] = []
    var total: Double?
    var service: String = ""        // DoorDash, Uber Eats…
    var sourceID: String?

    init(restaurant: String, cuisine: String, date: Date, dishes: [String], total: Double?, service: String) {
        self.restaurant = restaurant
        self.cuisine = cuisine
        self.date = date
        self.dishes = dishes
        self.total = total
        self.service = service
    }
}

// MARK: - Shared container (app + widget + Siri)

enum GardeStore {
    static let appGroup = "group.com.michaelkoonmen.garde"
    static let schema = Schema([PantryItem.self, Receipt.self, Spice.self, SavedRecipe.self, KitchenProfile.self,
                                ShoppingItem.self, MealPlanEntry.self, CookLog.self, BarBottle.self, TakeoutOrder.self])

    static let cloudContainer = "iCloud.com.michaelkoonmen.garde"

    /// Today's date in local time, "2026-11-05" (ISO formatting would use UTC and roll over at dinner time).
    static var dayKey: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The app syncs through the user's private iCloud database (when iCloud sync is on); the widget only reads locally.
    static var syncEnabled: Bool {
        UserDefaults(suiteName: appGroup)?.object(forKey: "icloudSync") as? Bool ?? true
    }

    static let container: ModelContainer = makeContainer(cloud: syncEnabled && !isExtension)
    static var isExtension: Bool { Bundle.main.bundlePath.hasSuffix(".appex") }

    /// True if the saved kitchen couldn't be opened this launch (shown as a warning, so data loss is never silent).
    nonisolated(unsafe) static var storeIsTemporary = false

    static func makeContainer(cloud: Bool) -> ModelContainer {
        // Automated tests: throwaway in-memory store (and no App Group entitlement in unsigned test builds).
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        }
        // An App Group config crashes (not throws) if the entitlement is missing, so check first.
        let hasGroup = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) != nil
        if cloud && hasGroup {
            let synced = ModelConfiguration(schema: schema, groupContainer: .identifier(appGroup),
                                            cloudKitDatabase: .private(cloudContainer))
            if let c = try? ModelContainer(for: schema, configurations: synced) { return c }
        }
        if hasGroup {
            let config = ModelConfiguration(schema: schema, groupContainer: .identifier(appGroup), cloudKitDatabase: .none)
            if let c = try? ModelContainer(for: schema, configurations: config) { return c }
        }
        // Fallback if the App Group isn't provisioned yet: app-only storage.
        if let c = try? ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .none)) { return c }
        // Last resort so the app still opens (data won't persist this launch).
        print("Garde: persistent store unavailable, using in-memory store")
        storeIsTemporary = true
        return try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }
}
