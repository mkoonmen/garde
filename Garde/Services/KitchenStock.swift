import Foundation
import SwiftData

struct IngredientAllocation: Identifiable {
    var id: UUID { item.id }
    let item: PantryItem
    var amount: FoodMeasure
}

struct IngredientRequirement: Identifiable {
    let id: Int
    let line: String
    let food: String
    let requested: FoodMeasure?
    var allocations: [IngredientAllocation]
    var shortfall: Double
    var needsCheck: Bool
    var isBasic: Bool
    var covered: Bool { isBasic || (shortfall <= 0.001 && !needsCheck) }
    var shoppingLine: String {
        guard let requested, !needsCheck else { return line }
        return FoodMeasure(value: max(0, shortfall), dimension: requested.dimension).label + " " + food
    }
}

enum KitchenStock {
    static func plan(_ lines: [String], items: [PantryItem]) -> [IngredientRequirement] {
        var remaining: [UUID: Double] = [:]
        let usable = items.filter { !$0.isUsedUp && !$0.isLeftover && ($0.daysLeft ?? 0) >= 0 && $0.remainingFraction > 0 }
            .sorted { ($0.daysLeft ?? 999) < ($1.daysLeft ?? 999) }
        for item in usable { remaining[item.id] = item.availableAmount?.value }
        return lines.enumerated().map { index, line in
            let food = RecipeScaler.foodName(line)
            let basic = ["salt", "black pepper", "pepper", "water", "olive oil", "oil", "cooking oil"].contains(food.lowercased())
            let requested = FoodMeasure.parse(line)
            let matches = usable.filter { FoodIdentity.matches(food, $0.ingredientName) }
            var need = requested?.value ?? 0
            var allocations: [IngredientAllocation] = []
            var uncertain = requested == nil
            if let requested {
                for item in matches {
                    guard let available = item.availableAmount, available.dimension == requested.dimension else { continue }
                    let take = min(need, remaining[item.id] ?? 0)
                    if take > 0 {
                        allocations.append(IngredientAllocation(item: item, amount: FoodMeasure(value: take, dimension: requested.dimension)))
                        remaining[item.id, default: 0] -= take
                        need -= take
                    }
                    if need < 0.001 { break }
                }
                if need > 0.001 && matches.contains(where: { $0.availableAmount?.dimension != requested.dimension }) { uncertain = true }
            }
            return IngredientRequirement(id: index, line: line, food: food, requested: requested, allocations: allocations,
                                         shortfall: basic ? 0 : need, needsCheck: basic ? false : uncertain, isBasic: basic)
        }
    }

    static func consume(_ requirements: [IngredientRequirement], selected: Set<Int>, operationID: UUID, context: ModelContext) throws {
        let events = try context.fetch(FetchDescriptor<KitchenEvent>())
        guard !events.contains(where: { $0.operationID == operationID }) else { return }
        for need in requirements where selected.contains(need.id) {
            for allocation in need.allocations {
                let item = allocation.item
                guard let current = item.availableAmount, current.dimension == allocation.amount.dimension,
                      current.value + 0.001 >= allocation.amount.value else { throw StockError.changed }
                item.recordChange("Used in cooking", explanation: "\(allocation.amount.label) for \(need.food).", operationID: operationID) {
                    item.remainingAmount = max(0, current.value - allocation.amount.value)
                    item.remainingFraction = item.originalAmount.map { $0.value > 0 ? item.remainingAmount! / $0.value : 0 } ?? 0
                    if item.remainingFraction < 0.001 {
                        item.isUsedUp = true; item.wasTossed = false; item.usedUpDate = .now; item.didRestockUsedUp = false
                    }
                    item.lastCheckedDate = .now
                }
            }
        }
    }

    /// Reconcile additive cooking deductions after iCloud delivers changes from another device.
    static func reconcileAmounts(context: ModelContext) throws {
        let events = try context.fetch(FetchDescriptor<KitchenEvent>())
        let items = try context.fetch(FetchDescriptor<PantryItem>())
        let unique = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { a, b in a.date > b.date ? a : b }).values
        for item in items {
            let history = unique.filter { $0.itemID == item.id }.sorted {
                $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date
            }
            guard let base = history.last(where: { !["Used in cooking", "Undo Used in cooking"].contains($0.action) }),
                  let data = base.after, let snapshot = try? JSONDecoder().decode(PantrySnapshot.self, from: data),
                  let initial = snapshot.measuredValue, let original = item.originalAmount, original.value > 0 else { continue }
            var value = initial
            for event in history where event.date > base.date && ["Used in cooking", "Undo Used in cooking"].contains(event.action) {
                guard let before = event.before.flatMap({ try? JSONDecoder().decode(PantrySnapshot.self, from: $0) }),
                      let after = event.after.flatMap({ try? JSONDecoder().decode(PantrySnapshot.self, from: $0) }),
                      let old = before.measuredValue, let new = after.measuredValue else { continue }
                value -= old - new
            }
            value = min(original.value, max(0, value))
            if abs((item.availableAmount?.value ?? 0) - value) > 0.001 {
                item.remainingAmount = value; item.remainingFraction = value / original.value
                item.isUsedUp = value < 0.001
                if item.isUsedUp { item.usedUpDate = history.last?.date; item.wasTossed = snapshot.wasTossed }
            }
        }
        if context.hasChanges { try context.save() }
    }

    static func register(_ item: PantryItem, context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<PantryItem>())) ?? []
        rememberDetails(for: item, existing: existing.filter { $0.id != item.id })
        context.insert(item)
        baseline(item, context: context)
    }

    static func baseline(_ item: PantryItem, context: ModelContext, existingEvents: [KitchenEvent]? = nil) {
        let events = existingEvents ?? ((try? context.fetch(FetchDescriptor<KitchenEvent>())) ?? [])
        guard !events.contains(where: { $0.itemID == item.id && $0.action == "Added" }) else { return }
        let event = KitchenEvent(itemID: item.id, action: "Added", explanation: item.store.map { "Bought at " + $0 } ?? "Added to your Kitchen.", before: nil, after: PantrySnapshot(item))
        event.id = item.id
        event.date = item.purchaseDate
        context.insert(event)
    }

    static func rememberDetails(for item: PantryItem, existing: [PantryItem]) {
        guard let previous = existing.filter({ $0.productKey == item.productKey || FoodIdentity.productKey($0.name) == FoodIdentity.productKey(item.name) }).max(by: { $0.purchaseDate < $1.purchaseDate }) else { return }
        item.ingredientOverride = previous.ingredientOverride
        item.packageAmount = previous.packageAmount
        item.packageUnit = previous.packageUnit
    }

    static func canUndo(_ event: KitchenEvent, item: PantryItem) -> Bool {
        guard !event.undone, event.before != nil, let data = event.after,
              var after = try? JSONDecoder().decode(PantrySnapshot.self, from: data) else { return false }
        let current = PantrySnapshot(item)
        after.didRestockUsedUp = current.didRestockUsedUp
        after.didRestockExpired = current.didRestockExpired
        after.lowRestockSuggested = current.lowRestockSuggested
        return after == current
    }

    static func undo(_ event: KitchenEvent, item: PantryItem, context: ModelContext) throws {
        guard canUndo(event, item: item), let data = event.before,
              let before = try? JSONDecoder().decode(PantrySnapshot.self, from: data) else { throw StockError.changed }
        item.recordChange("Undo " + event.action, explanation: "You undid the earlier change.") { before.apply(to: item) }
        event.undone = true
        try context.save()
    }

    enum StockError: LocalizedError {
        case changed
        var errorDescription: String? { "The Kitchen changed. Review the latest amounts and try again." }
    }
}
