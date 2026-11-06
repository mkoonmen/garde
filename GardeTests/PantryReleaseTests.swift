import Foundation
import SwiftData
import Testing
@testable import Garde

@MainActor
struct PantryReleaseTests {
    @Test func editCanBeCancelledAndPrintedDateRestored() throws {
        let sealed = try #require(Calendar.current.date(byAdding: .day, value: 200, to: Date.now))
        let item = PantryItem(name: "Jarred salsa", category: .condiments, location: .counter,
                              expirationDate: sealed, expirationIsEstimated: false)
        var draft = item.storage
        draft.open(name: item.name, category: item.category, on: .now)
        #expect(draft.location == .fridge)
        #expect(draft.expirationIsEstimated)
        #expect(item.location == .counter && !item.isOpened)
        #expect(item.expirationDate == sealed)
        item.storage = draft
        #expect(item.daysLeft == 14)
        item.unopen()
        #expect(item.location == .counter)
        #expect(!item.expirationIsEstimated && item.expirationDate == sealed)
    }

    @Test func openingWithoutASealedDateIsReversible() {
        let item = PantryItem(name: "Jarred salsa", category: .condiments, location: .freezer)
        item.open()
        #expect(item.location == .freezer)
        #expect(item.expirationDate != nil)
        item.unopen()
        #expect(item.expirationDate == nil && item.location == .freezer)
    }

    @Test func openingKeepsAnEarlierPrintedDateExact() throws {
        let printed = try #require(Calendar.current.date(byAdding: .day, value: 1, to: Date.now))
        let item = PantryItem(name: "Ketchup", category: .condiments, location: .pantry,
                              expirationDate: printed, expirationIsEstimated: false)
        item.open()
        #expect(item.expirationDate == printed && !item.expirationIsEstimated)
    }

    @Test(arguments: [("Pasta sauce", 5), ("Blue cheese dressing", 60), ("Steak sauce", 120), ("Applesauce", 7)])
    func jarRulesWinOverIngredients(name: String, days: Int) {
        let item = PantryItem(name: name, category: .condiments, location: .pantry)
        item.open()
        #expect(item.location == .fridge && item.daysLeft == days)
    }

    @Test func deletedRestockStaysDeletedUntilAnotherItemExpires() throws {
        let config = ModelConfiguration(schema: GardeStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: GardeStore.schema, configurations: config)
        let context = container.mainContext
        let suite = "garde.tests.restock." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        // These items also have a regular buying pace. The expiration gets priority and a single list entry.
        for daysAgo in [30, 20, 10] {
            let date = try #require(Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date.now))
            context.insert(PantryItem(name: "Milk", category: .dairy, purchaseDate: date, expirationDate: date))
        }
        ShoppingBrain.refreshRunningLow(context: context, defaults: defaults)
        let initial = try context.fetch(FetchDescriptor<ShoppingItem>())
        #expect(initial.map(\.reason) == ["Expired, restock"])
        #expect(defaults.stringArray(forKey: "restock.expired")?.count == 3)
        for entry in initial { context.delete(entry) }
        try context.save()
        ShoppingBrain.refreshRunningLow(context: context, defaults: defaults)
        #expect(try context.fetchCount(FetchDescriptor<ShoppingItem>()) == 0)

        context.insert(PantryItem(name: "Milk", category: .dairy, expirationDate: .distantPast))
        ShoppingBrain.refreshRunningLow(context: context, defaults: defaults)
        #expect(try context.fetchCount(FetchDescriptor<ShoppingItem>()) == 1)
    }
    @Test func usedUpHistoryRestocksEveryCategoryOnce() throws {
        let config = ModelConfiguration(schema: GardeStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: GardeStore.schema, configurations: config)
        let context = container.mainContext
        let products: [(String, FoodCategory)] = [
            ("Ocean Spray 100% Juice Cranberry", .beverages),
            ("Ghirardelli Sea salt caramel 454g", .sweets),
            ("Premium Sauce White Chocolate Flavored Sauce 16 oz", .condiments),
            ("Silk Silk Almond 64 FL OZ (2 QT) 1.89L", .beverages),
            ("Kirkland Signature Homogenized Milk 1 gal. (3.78L)", .dairy),
            ("Starbucks Pumpkin Spice Latte Creamer", .dairy)
        ]
        for (name, category) in products {
            let item = PantryItem(name: name, category: category)
            item.isUsedUp = true
            // Older history and missing timestamps must both be picked up.
            item.usedUpDate = category == .dairy ? nil : .distantPast
            context.insert(item)
        }
        ShoppingBrain.refreshRunningLow(context: context)
        var list = try context.fetch(FetchDescriptor<ShoppingItem>())
        #expect(Set(list.map(\.name)) == Set(products.map { $0.0 }))
        #expect(list.allSatisfy { $0.reason == "Ran out" })
        ShoppingBrain.refreshRunningLow(context: context)
        #expect(try context.fetchCount(FetchDescriptor<ShoppingItem>()) == 6)
        for entry in list { context.delete(entry) }
        try context.save()
        ShoppingBrain.refreshRunningLow(context: context)
        #expect(try context.fetchCount(FetchDescriptor<ShoppingItem>()) == 0)

        let restored = try #require(context.fetch(FetchDescriptor<PantryItem>()).first)
        restored.isUsedUp = false
        restored.markUsed()
        ShoppingBrain.refreshRunningLow(context: context)
        list = try context.fetch(FetchDescriptor<ShoppingItem>())
        #expect(list.map(\.name) == [restored.name])
    }

    @Test func restockWaitsUntilLastPackageIsFinishedAndSkipsLeftoversAndWaste() throws {
        let config = ModelConfiguration(schema: GardeStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: GardeStore.schema, configurations: config)
        let context = container.mainContext
        let finished = PantryItem(name: "Cranberry juice", category: .beverages)
        finished.markUsed()
        context.insert(finished)
        // An item without an expiration date is still in stock.
        let remaining = PantryItem(name: "Cranberry juice", category: .beverages)
        context.insert(remaining)
        let leftover = PantryItem(name: "Leftover chicken", category: .poultry)
        leftover.isLeftover = true
        leftover.markUsed()
        context.insert(leftover)
        let waste = PantryItem(name: "Moldy bread", category: .bakery)
        waste.markUsed(tossed: true)
        context.insert(waste)
        ShoppingBrain.refreshRunningLow(context: context)
        #expect(try context.fetchCount(FetchDescriptor<ShoppingItem>()) == 0)
        remaining.markUsed()
        ShoppingBrain.refreshRunningLow(context: context)
        let list = try context.fetch(FetchDescriptor<ShoppingItem>())
        #expect(list.map(\.name) == ["Cranberry juice"])
        #expect(finished.didRestockUsedUp && remaining.didRestockUsedUp)
    }

}
