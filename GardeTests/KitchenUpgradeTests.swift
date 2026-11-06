import Foundation
import SwiftData
import Testing
@testable import Garde

@MainActor
struct KitchenUpgradeTests {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: GardeStore.schema, configurations: ModelConfiguration(schema: GardeStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    @Test func productsKeepTheirBrandsWhileRecipeMatchingSeparatesPlantMilk() {
        #expect(FoodIdentity.ingredient("Kirkland Signature Homogenized Milk 1 gal.") == "milk")
        #expect(FoodIdentity.ingredient("Silk Silk Almond 64 FL OZ") == "almond milk")
        #expect(!FoodIdentity.matches("milk", "Silk almond milk"))
        #expect(!FoodIdentity.matches("butter", "peanut butter"))
        #expect(FoodIdentity.matches("chicken", "chicken thighs"))
        #expect(FoodIdentity.productKey("Kirkland milk 1 gal") != FoodIdentity.productKey("Organic Valley milk 1 gal"))
    }

    @Test func tablespoonsDeductFromAPintAndHistoryCanUndo() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let cream = PantryItem(name: "Heavy cream", category: .dairy, quantity: 1, unit: "pint", price: 5)
        context.insert(cream)
        KitchenStock.baseline(cream, context: context)
        cream.open()
        let original = try #require(cream.availableAmount)
        let plan = KitchenStock.plan(["2 tbsp heavy cream"], items: [cream])
        #expect(plan[0].covered)
        let operation = UUID()
        try KitchenStock.consume(plan, selected: [0], operationID: operation, context: context)
        try context.save()
        #expect(abs((cream.availableAmount?.value ?? 0) - (original.value - 29.5736)) < 0.01)
        #expect(!cream.isUsedUp)
        let after = cream.remainingAmount
        try KitchenStock.consume(plan, selected: [0], operationID: operation, context: context)
        #expect(cream.remainingAmount == after)
        let event = try #require(context.fetch(FetchDescriptor<KitchenEvent>()).first { $0.operationID == operation })
        #expect(KitchenStock.canUndo(event, item: cream))
        try KitchenStock.undo(event, item: cream, context: context)
        #expect(abs((cream.availableAmount?.value ?? 0) - original.value) < 0.01)
        #expect(event.undone)
        #expect(!KitchenStock.canUndo(event, item: cream))
    }

    @Test func incompatibleUnitsRequireConfirmationAndExpiredFoodIsExcluded() {
        let cream = PantryItem(name: "Cream", category: .dairy, quantity: 1, unit: "each")
        #expect(!KitchenStock.plan(["2 tbsp heavy cream"], items: [cream])[0].covered)
        let milk = PantryItem(name: "Milk", category: .dairy, quantity: 1000, unit: "ml", expirationDate: .distantPast)
        #expect(KitchenStock.plan(["100 ml milk"], items: [milk])[0].shortfall == 100)
    }

    @Test func twoDinnersShareOneCartonAndProduceOneMeasuredShoppingEntry() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let cream = PantryItem(name: "Heavy cream", category: .dairy, quantity: 200, unit: "ml")
        context.insert(cream)
        for title in ["First dinner", "Second dinner"] {
            context.insert(MealPlanEntry(day: .now, title: title, summary: "", minutes: 20, servings: 2,
                                         ingredients: ["150 ml heavy cream"], steps: ["Warm gently."], needToBuy: []))
        }
        try MealShopping.reconcile(context: context)
        let list = try context.fetch(FetchDescriptor<ShoppingItem>())
        #expect(list.count == 1)
        #expect(list.first?.quantityNote == "100 ml")
        #expect(list.first?.reason.contains("First dinner") == false || list.first?.reason.contains("Second dinner") == true)
        try MealShopping.reconcile(context: context)
        #expect(try context.fetchCount(FetchDescriptor<ShoppingItem>()) == 1)
        list[0].isDismissed = true
        try context.save()
        try MealShopping.reconcile(context: context)
        #expect(list[0].isDismissed)
    }

    @Test func partialAmountCostUsesThePurchasedPackagePrice() {
        let cream = PantryItem(name: "Heavy cream", category: .dairy, quantity: 500, unit: "ml", price: 5)
        let cost = CostCalculator.estimate(ingredients: ["100 ml heavy cream"], items: [cream])
        #expect(cost.matched == 1)
        #expect(abs(cost.total - 1) < 0.001)
    }

    @Test func changedStockPreventsAnObsoleteUndo() throws {
        let container = try makeContainer()
        let item = PantryItem(name: "Milk", category: .dairy)
        container.mainContext.insert(item)
        item.setRemaining(0.5)
        let event = try #require(container.mainContext.fetch(FetchDescriptor<KitchenEvent>()).first)
        item.setRemaining(0.1)
        #expect(!KitchenStock.canUndo(event, item: item))
    }

    @Test func fixedMethodsAreCompleteAndFallbacksRespectAllergiesAndNeverAgain() {
        for recipe in RecipeFoundation.basics { #expect(RecipeFoundation.check(recipe).valid) }
        let profile = KitchenProfile()
        profile.allergies = ["milk", "eggs", "fish"]
        let log = CookLog(title: "Tomato garlic pasta", rating: 1, neverAgain: true)
        let candidates = RecipeFoundation.candidates(items: [], profile: profile, logs: [log])
        #expect(!candidates.contains { $0.title == log.title })
        #expect(candidates.allSatisfy { AllergenGuard.violations(in: $0.ingredients + $0.steps, allergies: profile.allergies).isEmpty })
        #expect(!candidates.isEmpty)
    }

    @Test func recipeChecksCatchImpossibleTimingAndMissingIngredients() {
        let recipe = RecipeIdea(title: "Quick pasta", summary: "", minutes: 10, servings: 2,
                                ingredients: ["100 g pasta"], steps: ["Simmer chicken for 45 minutes."], usesFromKitchen: [])
        let check = RecipeFoundation.check(recipe)
        #expect(!check.valid)
        #expect(check.notes.contains { $0.contains("chicken") })
    }

    @Test func preferencesAndStockHistorySurviveBackupRestore() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let profile = KitchenProfile()
        profile.householdMemory = ["Less lemon in piccata"]
        profile.preferredStore = "ALDI"
        context.insert(profile)
        let item = PantryItem(name: "Cream", category: .dairy)
        item.ingredientOverride = "heavy cream"; item.packageAmount = 500; item.packageUnit = "ml"
        context.insert(item)
        item.setRemaining(0.5)
        try context.save()
        let url = try DataExport.exportJSON(context: context)
        let restored = try makeContainer()
        _ = try DataExport.importJSON(from: url, context: restored.mainContext)
        let copy = try #require(restored.mainContext.fetch(FetchDescriptor<PantryItem>()).first)
        #expect(copy.id == item.id && copy.ingredientName == "heavy cream")
        #expect(copy.availableAmount?.value == 250)
        #expect(try restored.mainContext.fetchCount(FetchDescriptor<KitchenEvent>()) == 1)
        let memory = try #require(restored.mainContext.fetch(FetchDescriptor<KitchenProfile>()).first)
        #expect(memory.householdMemory == profile.householdMemory && memory.preferredStore == "ALDI")
    }
}
