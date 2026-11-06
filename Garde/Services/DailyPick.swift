import Foundation
import SwiftData

/// One dinner idea a day, built around what expires first. Made once per day on the phone and kept until tomorrow.
@MainActor
@Observable
final class DailyPick {
    static let shared = DailyPick()

    struct Pick: Codable, Equatable {
        var day: String
        var title, summary: String
        var minutes, servings: Int
        var ingredients, steps: [String]
    }

    private(set) var pick: Pick? = {
        guard let d = UserDefaults.standard.data(forKey: "dailyPick") else { return nil }
        return try? JSONDecoder().decode(Pick.self, from: d)
    }()
    private(set) var working = false

    private static var today: String { Date.now.formatted(.iso8601.year().month().day()) }
    var isFresh: Bool { pick?.day == Self.today }

    func refreshIfNeeded(items: [PantryItem], spices: [Spice], profile: KitchenProfile?, logs: [CookLog], force: Bool = false) async {
        guard force || !isFresh, !working, let profile, items.count >= 3 else { return }
        let chef = ChefAI()
        guard chef.state == .available else { return }
        working = true; defer { working = false }
        let soon = items.filter { ($0.daysLeft ?? 99) <= 3 }.prefix(3).map(\.name)
        let req = ChefAI.RecipeRequest(mood: "Tonight's dinner, weeknight easy", maxMinutes: 45, mustUse: Array(soon))
        guard let out = try? await chef.suggestRecipes(items: items, spices: spices, profile: profile, logs: logs, request: req),
              let r = out.recipes.first else { return }
        let p = Pick(day: Self.today, title: r.title, summary: r.summary, minutes: r.minutes, servings: r.servings,
                     ingredients: r.ingredients, steps: r.steps)
        pick = p
        if let d = try? JSONEncoder().encode(p) { UserDefaults.standard.set(d, forKey: "dailyPick") }
    }
}
