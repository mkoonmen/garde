import Foundation
import SwiftData

/// Allocate stock across the entire plan before combining the remaining compatible amounts.
enum MealShopping {
    struct Demand {
        var food: String
        var measure: FoodMeasure?
        var notes: [String]
        var sources: [String]
        var titles: [String]
    }
    static func reconcile(context: ModelContext) throws {
        let today = Calendar.current.startOfDay(for: Date.now)
        let plans = try context.fetch(FetchDescriptor<MealPlanEntry>()).filter { !$0.isCooked && $0.day >= today }
            .sorted { $0.day == $1.day ? $0.id.uuidString < $1.id.uuidString : $0.day < $1.day }
        let items = try context.fetch(FetchDescriptor<PantryItem>())
        let list = try context.fetch(FetchDescriptor<ShoppingItem>())
        var lines: [String] = [], owners: [MealPlanEntry] = []
        for plan in plans {
            for line in plan.ingredients { lines.append(line); owners.append(plan) }
        }
        let requirements = KitchenStock.plan(lines, items: items)
        var demands: [String: Demand] = [:]
        for need in requirements where !need.covered {
            let owner = owners[need.id]
            let food = FoodIdentity.ingredient(need.food)
            let dimension = need.needsCheck ? "check" : (need.requested?.dimension.rawValue ?? "check")
            let key = food + "/" + dimension
            let amount = need.needsCheck ? nil : need.requested.map { FoodMeasure(value: need.shortfall, dimension: $0.dimension) }
            var demand = demands[key] ?? Demand(food: food, measure: amount.map { FoodMeasure(value: 0, dimension: $0.dimension) }, notes: [], sources: [], titles: [])
            if let amount { demand.measure?.value += amount.value }
            else { demand.notes.append(need.line) }
            demand.sources.append(owner.id.uuidString + "/" + need.line)
            demand.titles.append(owner.day.formatted(.dateTime.weekday(.abbreviated)) + " " + owner.title)
            demands[key] = demand
        }
        for plan in plans {
            plan.needToBuy = requirements.filter { owners[$0.id].id == plan.id && !$0.covered }.map(\.shoppingLine)
        }
        for item in list { item.mealNote = "" }
        for item in list where !item.planDemandKey.isEmpty && demands[item.planDemandKey] == nil {
            if !item.isChecked { context.delete(item) }
        }
        for (key, demand) in demands.sorted(by: { $0.key < $1.key }) {
            let amount = demand.measure?.label ?? Array(Set(demand.notes)).joined(separator: "; ")
            let reason = "For " + Array(Set(demand.titles)).sorted().joined(separator: "; ")
            if let usual = list.first(where: { $0.isSpecificProduct && !$0.isChecked && !$0.isDismissed && FoodIdentity.matches(demand.food, $0.name) }) {
                usual.mealNote = amount + " needed · " + reason
                continue
            }
            let sources = demand.sources.sorted().joined(separator: "|")
            if let existing = list.first(where: { $0.planDemandKey == key }) {
                if existing.planSourcesKey != sources { existing.isChecked = false; existing.isDismissed = false }
                existing.quantityNote = amount; existing.reason = reason; existing.planSourcesKey = sources
            } else {
                let item = ShoppingItem(name: demand.food.capitalized, category: ShoppingBrain.guessCategory(demand.food), quantityNote: amount, reason: reason)
                item.planDemandKey = key; item.planSourcesKey = sources
                context.insert(item)
            }
        }
        if context.hasChanges { try context.save() }
    }
}
