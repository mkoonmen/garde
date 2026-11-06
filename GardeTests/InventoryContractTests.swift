import Foundation
import Testing
#if canImport(GardeCore)
@testable import GardeCore
#else
@testable import Garde
#endif

@MainActor
struct InventoryContractTests {
    @Test func everyChefFeatureReceivesAvailableStockBeforeApplyingItsLimit() {
        let expired = PantryItem(name: "Expired milk", category: .dairy, quantity: 500, unit: "ml", expirationDate: .distantPast)
        let finished = PantryItem(name: "Finished milk", category: .dairy)
        finished.isUsedUp = true
        let empty = PantryItem(name: "Empty milk", category: .dairy, quantity: 0, unit: "ml")
        let available = PantryItem(name: "Kirkland milk", category: .dairy, quantity: 500, unit: "ml")
        available.setRemaining(0.5)
        let text = KitchenInventory.text([expired, finished, empty, available], limit: 1)
        #expect(text.contains("Kirkland milk"))
        #expect(text.contains("250 ml left"))
        #expect(text.contains("recipe ingredient milk"))
        #expect(!text.contains("Expired milk"))
        #expect(!text.contains("Finished milk"))
        #expect(!text.contains("Empty milk"))
    }

    @Test func unknownDatesAndCookedLeftoversRemainExplicit() {
        let item = PantryItem(name: "Cooked chicken", category: .poultry)
        item.isLeftover = true
        item.expirationDate = nil
        let text = KitchenInventory.text([item])
        #expect(text.contains("LEFTOVER, already cooked"))
        #expect(text.contains("no date"))
        #expect(KitchenInventory.text([item], limit: 0).isEmpty)
    }
}
