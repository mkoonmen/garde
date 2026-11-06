import Foundation

/// The same available stock and measured amounts are presented to every cooking feature.
enum KitchenInventory {
    static func available(_ items: [PantryItem]) -> [PantryItem] {
        items.filter { $0.hasStock && ($0.daysLeft ?? 0) >= 0 }
    }

    static func text(_ items: [PantryItem], limit: Int = 60) -> String {
        available(items).prefix(max(0, limit)).map { item -> String in
            let date = item.daysLeft.map { "\($0)d left" } ?? "no date"
            let tag = item.isLeftover ? " [LEFTOVER, already cooked]" : ""
            return "- \(item.name)\(tag) (\(item.availableLabel), recipe ingredient \(item.ingredientName), \(item.location.label), \(date))"
        }.joined(separator: "\n")
    }
}
