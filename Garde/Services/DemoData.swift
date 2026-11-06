#if DEBUG
import Foundation
import SwiftData

/// Simulator-only sample kitchen for screenshots and UI checks. Never compiled into TestFlight builds (Release).
/// Launch with `-demoData YES` (and optionally `-startTab 2`).
enum DemoData {
    @MainActor static func seedIfAsked(context: ModelContext) {
        guard UserDefaults.standard.bool(forKey: "demoData"),
              ((try? context.fetchCount(FetchDescriptor<PantryItem>())) ?? 0) == 0 else { return }
        let day: (Int) -> Date = { Calendar.current.date(byAdding: .day, value: $0, to: .now)! }
        let items: [(String, FoodCategory, StorageLocation, Int?, Double?)] = [
            ("Boneless Skinless Chicken Thighs", .poultry, .fridge, 1, 9.87), ("Baby Spinach", .produce, .fridge, 2, 4.99),
            ("Fresh Mozzarella", .cheese, .fridge, 5, 5.49), ("Large Brown Eggs", .eggs, .fridge, 20, 5.49),
            ("Atlantic Salmon Fillet", .seafood, .freezer, 60, 17.49), ("Ribeye Steak", .meat, .freezer, 90, 24.0),
            ("Heavy Cream", .dairy, .fridge, 0, 3.29), ("Lemons", .fruit, .counter, 6, 2.99), ("Arborio Rice", .grains, .pantry, 300, 4.49),
            ("Chicken Broth", .canned, .pantry, 400, 2.79), ("Shallots", .produce, .pantry, 14, 2.49), ("Brie", .cheese, .fridge, 12, 7.99),
        ]
        for (n, c, l, d, p) in items {
            let i = PantryItem(name: n, category: c, location: l, purchaseDate: day(-3), expirationDate: d.map(day), price: p, store: "Stop & Shop")
            if l == .freezer { i.frozenDate = day(-120) }
            context.insert(i)
        }
        let old = PantryItem(name: "Baby Spinach", category: .produce, purchaseDate: day(-20), price: 3.99, store: "ALDI")
        old.isUsedUp = true; old.usedUpDate = day(-12); context.insert(old)
        let tossed = PantryItem(name: "Cilantro", category: .produce, purchaseDate: day(-6), price: 1.49, store: "Stop & Shop")
        tossed.isUsedUp = true; tossed.wasTossed = true; tossed.usedUpDate = day(-1); context.insert(tossed)
        context.insert(Receipt(store: "Stop & Shop", date: day(-3), total: 96.40))
        ["Smoked Paprika", "Cumin", "Thyme", "Chili Flakes"].forEach { context.insert(Spice(name: $0)) }
        context.insert(BarBottle(name: "Woodford Reserve Double Oaked", kind: .bourbon, count: 1))
        context.insert(BarBottle(name: "Buffalo Trace", kind: .bourbon, count: 2))
        context.insert(BarBottle(name: "Sancerre", kind: .white, vintage: "2022", region: "Loire", count: 2))
        let r = SavedRecipe(title: "Lemon Chicken Piccata", summary: "Crisp thighs, bright lemon-caper pan sauce.", minutes: 35, servings: 2,
                            ingredients: ["1 1/2 lb chicken thighs", "2 tbsp capers", "1/2 cup chicken broth", "1 lemon", "2-3 cloves garlic"],
                            steps: ["Season and sear the chicken 6 minutes per side.", "Make the pan sauce.", "Simmer 3 minutes and serve."])
        context.insert(r)
        let log = CookLog(title: r.title, rating: 5); log.date = day(-30); context.insert(log)
        context.insert(TakeoutOrder(restaurant: "Thai Basil", cuisine: "Thai", date: day(-5), dishes: ["Pad See Ew", "Tom Kha Soup"], total: 38.5, service: "DoorDash"))
        context.insert(TakeoutOrder(restaurant: "Thai Basil", cuisine: "Thai", date: day(-19), dishes: ["Pad See Ew", "Spring Rolls"], total: 31.0, service: "Uber Eats"))
        context.insert(TakeoutOrder(restaurant: "Shake Shack", cuisine: "Burgers", date: day(-9), dishes: ["ShackBurger", "Crinkle Fries"], total: 24.7, service: "Uber Eats"))
        context.insert(ShoppingItem(name: "Baby Spinach", category: .produce, reason: "Running low"))
        context.insert(ShoppingItem(name: "Eggs", category: .eggs))
        try? context.save()
    }
}
#endif
