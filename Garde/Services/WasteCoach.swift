import Foundation

/// Learns quietly from what you finish versus what you throw out, and turns it into small nudges:
/// a tip on the shopping list ("you've tossed this 3 times, buy a smaller one") and a note for the week planner
/// so it schedules those foods early.
enum WasteCoach {
    struct Record { var tossed = 0; var finished = 0; var name = "" }

    /// Per-food tallies over the last 90 days of used-up items.
    static func records(_ everything: [PantryItem], now: Date = .now) -> [String: Record] {
        let since = now.addingTimeInterval(-90 * 86_400)
        var out: [String: Record] = [:]
        for i in everything where i.isUsedUp && !i.isLeftover && (i.usedUpDate ?? .distantPast) >= since {
            let k = ShoppingBrain.key(i.name)
            guard !k.isEmpty else { continue }
            var r = out[k] ?? Record(name: i.name)
            if i.wasTossed { r.tossed += 1 } else { r.finished += 1 }
            out[k] = r
        }
        return out
    }

    /// Foods you throw out at least twice and at least as often as you finish them.
    static func oftenWasted(_ everything: [PantryItem]) -> [Record] {
        records(everything).values.filter { $0.tossed >= 2 && $0.tossed >= $0.finished }.sorted { $0.tossed > $1.tossed }
    }

    /// A shopping-list tip for this name, if it's something that usually goes to waste.
    static func tip(for name: String, wasted: [Record]) -> String? {
        guard let r = wasted.first(where: { ShoppingBrain.appears($0.name, in: name) || ShoppingBrain.appears(name, in: $0.name) }) else { return nil }
        let total = r.tossed + r.finished
        return "Tossed \(r.tossed) of the last \(total). Try a smaller size, or freeze half when you get home."
    }

    /// One line for the week planner.
    static func plannerNote(_ everything: [PantryItem]) -> String {
        let names = oftenWasted(everything).prefix(6).map(\.name)
        guard !names.isEmpty else { return "" }
        return " These often go to waste here, so use them early in the week and in more than one dinner: \(names.joined(separator: ", "))."
    }
}
