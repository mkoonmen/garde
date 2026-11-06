import Foundation
import SwiftData

struct PantrySnapshot: Codable, Equatable {
    var name, categoryRaw, locationRaw, unit, ingredientOverride, packageUnit: String
    var quantity, packageAmount, remainingFraction: Double
    var remainingAmount: Double?
    var expirationDate, openedDate, unopenedExpiration, frozenDate, usedUpDate: Date?
    var expirationIsEstimated, isUsedUp, wasTossed, didRestockUsedUp, didRestockExpired: Bool
    var unopenedExpirationIsEstimated: Bool?
    var unopenedLocationRaw: String?

    init(_ item: PantryItem) {
        name = item.name; categoryRaw = item.categoryRaw; locationRaw = item.locationRaw; unit = item.unit
        ingredientOverride = item.ingredientOverride; packageUnit = item.packageUnit
        quantity = item.quantity; packageAmount = item.packageAmount; remainingFraction = item.remainingFraction
        remainingAmount = item.remainingAmount; expirationDate = item.expirationDate; openedDate = item.openedDate
        unopenedExpiration = item.unopenedExpiration; frozenDate = item.frozenDate; usedUpDate = item.usedUpDate
        expirationIsEstimated = item.expirationIsEstimated; isUsedUp = item.isUsedUp; wasTossed = item.wasTossed
        didRestockUsedUp = item.didRestockUsedUp; didRestockExpired = item.didRestockExpired
        unopenedExpirationIsEstimated = item.unopenedExpirationIsEstimated; unopenedLocationRaw = item.unopenedLocationRaw
    }

    var measuredValue: Double? {
        if isUsedUp { return 0 }
        var original = FoodMeasure.amount(quantity, unit: unit)
        if packageAmount > 0, let size = FoodMeasure.amount(packageAmount, unit: packageUnit) { original = FoodMeasure(value: size.value * quantity, dimension: size.dimension) }
        else if ["each", "pack", "bottle", "jar", "carton"].contains(unit), let size = FoodMeasure.package(in: name) { original = FoodMeasure(value: size.value * quantity, dimension: size.dimension) }
        return remainingAmount ?? original.map { $0.value * remainingFraction }
    }

    func apply(to item: PantryItem) {
        item.name = name; item.categoryRaw = categoryRaw; item.locationRaw = locationRaw; item.unit = unit
        item.ingredientOverride = ingredientOverride; item.packageUnit = packageUnit
        item.quantity = quantity; item.packageAmount = packageAmount; item.remainingFraction = remainingFraction
        item.remainingAmount = remainingAmount; item.expirationDate = expirationDate; item.openedDate = openedDate
        item.unopenedExpiration = unopenedExpiration; item.frozenDate = frozenDate; item.usedUpDate = usedUpDate
        item.expirationIsEstimated = expirationIsEstimated; item.isUsedUp = isUsedUp; item.wasTossed = wasTossed
        item.didRestockUsedUp = didRestockUsedUp; item.didRestockExpired = didRestockExpired
        item.unopenedExpirationIsEstimated = unopenedExpirationIsEstimated; item.unopenedLocationRaw = unopenedLocationRaw
    }
}

@Model
final class KitchenEvent {
    var id: UUID = UUID()
    var itemID: UUID = UUID()
    var date: Date = Date()
    var action: String = ""
    var explanation: String = ""
    var before: Data?
    var after: Data?
    var undone = false
    var operationID: UUID?

    init(itemID: UUID, action: String, explanation: String, before: PantrySnapshot?, after: PantrySnapshot, operationID: UUID? = nil) {
        self.itemID = itemID; self.action = action; self.explanation = explanation; self.operationID = operationID
        self.before = before.flatMap { try? JSONEncoder().encode($0) }
        self.after = try? JSONEncoder().encode(after)
    }
}

extension PantryItem {
    func recordChange(_ action: String, explanation: String, operationID: UUID? = nil, _ change: () -> Void) {
        let before = PantrySnapshot(self)
        change()
        let after = PantrySnapshot(self)
        guard before != after, let context = modelContext else { return }
        context.insert(KitchenEvent(itemID: id, action: action, explanation: explanation, before: before, after: after, operationID: operationID))
    }

    func setRemaining(_ fraction: Double) {
        recordChange("Amount checked", explanation: "You checked how much remains.") {
            remainingFraction = min(1, max(0, fraction))
            remainingAmount = originalAmount.map { $0.value * remainingFraction }
            isUsedUp = remainingFraction == 0
            wasTossed = false
            usedUpDate = isUsedUp ? .now : nil
            if isUsedUp { didRestockUsedUp = false }
            lastCheckedDate = .now
        }
    }

    func restore() {
        recordChange("Restored", explanation: "You restored this item to the Kitchen.") {
            isUsedUp = false; wasTossed = false; usedUpDate = nil
            if remainingFraction == 0 { remainingFraction = 1; remainingAmount = nil }
            lastCheckedDate = .now
        }
    }
}
