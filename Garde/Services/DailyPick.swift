import Foundation
import SwiftData
import WidgetKit

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
    private(set) var problem: String?
    private var seenToday: [String] = []   // titles already shown today, so Refresh brings something new

    private static var today: String { GardeStore.dayKey }
    var isFresh: Bool { pick?.day == Self.today }

    func refreshIfNeeded(items: [PantryItem], spices: [Spice], profile: KitchenProfile?, logs: [CookLog], force: Bool = false) async {
        let tried = UserDefaults.standard.string(forKey: "dailyPick.tried")
        guard force || (!isFresh && tried != Self.today), !working, let profile else { return }
        let fresh = items.filter { ($0.daysLeft ?? 99) >= 0 }
        problem = nil
        guard fresh.count >= 3 else { if force { problem = "Add a few more things to your kitchen first." }; return }
        let chef = ChefAI()
        guard chef.state == .available else {
            if force, case .unavailable(let why) = chef.state { problem = why }
            return
        }
        working = true; defer { working = false }
        if !force {   // let launch finish first, and only try once a day if it fails
            try? await Task.sleep(for: .seconds(3))
            if Task.isCancelled { return }
            UserDefaults.standard.set(Self.today, forKey: "dailyPick.tried")
        }
        let soon = fresh.filter { ($0.daysLeft ?? 99) <= 3 }.sorted { ($0.daysLeft ?? 99) < ($1.daysLeft ?? 99) }.prefix(3).map(\.name)
        if let t = pick?.title, !seenToday.contains(t) { seenToday.append(t) }
        let styles = ["weeknight easy", "something different from usual", "cozy", "bright and fresh", "restaurant-style", "one-pan"]
        let avoid = seenToday.isEmpty ? "" : " Not any of these: \(seenToday.joined(separator: ", "))."
        let req = ChefAI.RecipeRequest(mood: "Tonight's dinner, \(force ? styles.randomElement()! : styles[0]).\(avoid)", maxMinutes: 45, mustUse: Array(soon))
        let out: (recipes: [RecipeIdea], blocked: Int)
        do { out = try await chef.suggestRecipes(items: fresh, spices: spices, profile: profile, logs: logs, request: req) }
        catch { problem = "The chef couldn't come up with one just now. Try again."; return }
        guard let r = out.recipes.first(where: { !seenToday.contains($0.title) }) ?? out.recipes.first else {
            problem = out.blocked > 0 ? "Those ideas used one of your allergens, so they were skipped. Try again." : "No idea came back. Try again."
            return
        }
        let p = Pick(day: Self.today, title: r.title, summary: r.summary, minutes: r.minutes, servings: r.servings,
                     ingredients: r.ingredients, steps: r.steps)
        pick = p
        if let d = try? JSONEncoder().encode(p) { UserDefaults.standard.set(d, forKey: "dailyPick") }
        // The widget shows tonight's idea when nothing is planned.
        let shared = UserDefaults(suiteName: GardeStore.appGroup)
        shared?.set(p.title, forKey: "dailyPick.title"); shared?.set(p.day, forKey: "dailyPick.day")
        WidgetCenter.shared.reloadAllTimelines()
    }
}
