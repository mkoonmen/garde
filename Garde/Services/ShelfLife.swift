import Foundation

/// Conservative default shelf lives (days) used when a package date isn't known.
/// Based on general USDA / FoodKeeper guidance. Always editable per item.
enum ShelfLife {
    static func days(for category: FoodCategory, in location: StorageLocation) -> Int {
        switch (category, location) {
        case (_, .freezer):
            switch category {
            case .seafood: return 90
            case .bakery: return 90
            default: return 180
            }
        case (.meat, _): return 3
        case (.poultry, _): return 2
        case (.seafood, _): return 2
        case (.deli, _): return 5
        case (.dairy, _): return 7
        case (.cheese, _): return 21
        case (.eggs, _): return 28
        case (.produce, .counter): return 5
        case (.produce, _): return 7
        case (.fruit, .counter): return 4
        case (.fruit, _): return 10
        case (.bakery, _): return 5
        case (.condiments, _): return 120
        case (.grains, _), (.canned, _), (.snacks, _): return 365
        case (.beverages, _): return 30
        case (.frozen, _): return 3
        case (.other, _): return 14
        }
    }

    static func estimatedExpiration(for category: FoodCategory, in location: StorageLocation, from purchase: Date = .now) -> Date {
        Calendar.current.date(byAdding: .day, value: days(for: category, in: location), to: purchase) ?? purchase
    }

    /// Best-guess storage spot for a category.
    static func defaultLocation(for category: FoodCategory) -> StorageLocation {
        switch category {
        case .meat, .poultry, .seafood, .dairy, .cheese, .eggs, .deli, .produce, .condiments: .fridge
        case .frozen: .freezer
        case .fruit: .counter
        default: .pantry
        }
    }
}
