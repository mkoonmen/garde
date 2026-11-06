import Foundation
import SwiftData
import WidgetKit

@MainActor
@Observable
final class DailyPick {
    static let shared = DailyPick()
    enum Mode: String, Codable, CaseIterable, Identifiable {
        case useHere = "Use what’s here", quick = "Quick and easy", loved = "Something you’ll love"
        var id: String { rawValue }
    }
    struct Pick: Codable, Equatable, Identifiable {
        var day: String
        var title, summary: String
        var minutes, servings: Int
        var ingredients, steps: [String]
        var id: String { day + title }
        var recipe: RecipeIdea { RecipeIdea(title: title, summary: summary, minutes: minutes, servings: servings, ingredients: ingredients, steps: steps, usesFromKitchen: []) }
    }
    struct Choice: Identifiable {
        var id: Mode { mode }
        let mode: Mode
        let pick: Pick
        let explanation: String
    }
    private(set) var pick: Pick?
    private(set) var choices: [Choice] = []
    private(set) var working = false
    private(set) var problem: String?
    private var generated: [RecipeIdea] = []
    private var favoriteTitles: Set<String> = []
    var isFresh: Bool { pick?.day == GardeStore.dayKey }

    func refreshIfNeeded(items: [PantryItem], spices: [Spice], profile: KitchenProfile?, logs: [CookLog], force: Bool = false, easier: Bool = false) async {
        guard let profile else { return }
        let saved = (try? GardeStore.container.mainContext.fetch(FetchDescriptor<SavedRecipe>())) ?? []
        favoriteTitles = Set(saved.filter(\.isFavorite).map { $0.title.lowercased() })
        let local = RecipeFoundation.candidates(items: items, profile: profile, logs: logs, saved: saved)
            .filter { !easier || $0.minutes <= min(20, profile.weeknightMinutes) }
        let limit = easier ? min(20, profile.weeknightMinutes) : profile.weeknightMinutes
        buildChoices(pool: local + generated.filter { !easier || $0.minutes <= limit }, items: items, profile: profile, logs: logs, limit: limit)
        guard !working else { return }
        let tried = UserDefaults.standard.string(forKey: "dailyPick.tried")
        guard force || tried != GardeStore.dayKey else { return }
        let chef = ChefAI()
        guard chef.state == .available else {
            problem = choices.isEmpty ? "Add a saved recipe or adjust your preferences to find dinner." : "Showing saved recipes and Garde basic methods."
            return
        }
        working = true
        defer { working = false }
        UserDefaults.standard.set(GardeStore.dayKey, forKey: "dailyPick.tried")
        let soon = items.filter { !$0.isUsedUp && ($0.daysLeft ?? 99) >= 0 && ($0.daysLeft ?? 99) <= 3 }
            .sorted { ($0.daysLeft ?? 99) < ($1.daysLeft ?? 99) }.prefix(3).map(\.name)
        do {
            let request = ChefAI.RecipeRequest(mood: "Three practical dinner choices: use what is here, quick and easy, and a household favorite.", maxMinutes: easier ? limit : max(limit, 45), mustUse: Array(soon))
            let out = try await chef.suggestRecipes(items: items, spices: spices, profile: profile, logs: logs, request: request)
            guard !Task.isCancelled else { return }
            generated = out.recipes
            problem = nil
            buildChoices(pool: local + generated.filter { !easier || $0.minutes <= limit }, items: items, profile: profile, logs: logs, limit: limit)
        } catch is CancellationError { return }
        catch { problem = "Fresh ideas couldn’t load. Your available recipes are ready below." }
    }

    private func buildChoices(pool: [RecipeIdea], items: [PantryItem], profile: KitchenProfile, logs: [CookLog], limit: Int) {
        var seen: Set<String> = []
        let never = Set(logs.filter(\.neverAgain).map { $0.title.lowercased() })
        let safe = pool.filter { r in
            seen.insert(r.title.lowercased()).inserted && !never.contains(r.title.lowercased()) && RecipeFoundation.check(r).valid &&
            AllergenGuard.violations(in: [r.title] + r.ingredients + r.steps, allergies: profile.allergies).isEmpty
        }
        let loved = Set(logs.filter { $0.rating >= 4 }.map { $0.title.lowercased() })
        var chosen: Set<String> = []
        choices = Mode.allCases.compactMap { mode in
            let candidates = mode == .quick ? safe.filter { $0.minutes <= limit } : safe
            let ordered = candidates.sorted { a, b in
                func score(_ r: RecipeIdea) -> Double {
                    let needs = KitchenStock.plan(r.ingredients, items: items)
                    let covered = needs.filter(\.covered).count
                    let soon = needs.flatMap(\.allocations).filter { ($0.item.daysLeft ?? 99) <= 3 }.count
                    switch mode {
                    case .useHere: return Double(covered * 8 + soon * 12 - needs.filter { !$0.covered }.count * 5)
                    case .quick: return Double(covered * 2 - r.minutes)
                    case .loved:
                        let favoriteIngredients = r.ingredients.filter { line in profile.loves.contains { FoodIdentity.contains($0, in: line) } }.count
                        return Double((loved.contains(r.title.lowercased()) || favoriteTitles.contains(r.title.lowercased()) ? 100 : 0) + favoriteIngredients * 10 + covered)
                    }
                }
                let x = score(a), y = score(b)
                return x == y ? a.title < b.title : x > y
            }
            guard let recipe = ordered.first(where: { !chosen.contains($0.title) }) ?? ordered.first else { return nil }
            chosen.insert(recipe.title)
            let needs = KitchenStock.plan(recipe.ingredients, items: items)
            let missing = needs.filter { !$0.covered }
            let soon = needs.flatMap(\.allocations).filter { ($0.item.daysLeft ?? 99) <= 3 }.map { $0.item.name }
            var why = missing.isEmpty ? "Recorded amounts cover the ingredients." : "\(missing.count) ingredient\(missing.count == 1 ? "" : "s") to buy or check."
            if let first = soon.first { why += " Uses \(first), which needs using soon." }
            if mode == .loved && loved.contains(recipe.title.lowercased()) { why += " You rated this highly." }
            let p = Pick(day: GardeStore.dayKey, title: recipe.title, summary: recipe.summary, minutes: recipe.minutes,
                         servings: recipe.servings, ingredients: recipe.ingredients, steps: recipe.steps)
            return Choice(mode: mode, pick: p, explanation: why)
        }
        pick = choices.first?.pick
        let shared = UserDefaults(suiteName: GardeStore.appGroup)
        shared?.set(pick?.title, forKey: "dailyPick.title")
        shared?.set(pick?.day, forKey: "dailyPick.day")
        WidgetCenter.shared.reloadAllTimelines()
    }
}
