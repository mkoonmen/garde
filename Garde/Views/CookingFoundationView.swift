import SwiftUI
import SwiftData

/// Useful cooking choices remain available while a fresh AI answer is unavailable.
struct CookingFoundationLink: View {
    var guestAllergies: [String] = []
    var body: some View {
        NavigationLink {
            CookingFoundationView(guestAllergies: guestAllergies)
        } label: {
            Label("Choose a saved recipe or basic method", systemImage: "book.closed")
        }
    }
}

struct CookingFoundationView: View {
    @Query private var profiles: [KitchenProfile]
    @Query private var logs: [CookLog]
    @Query(sort: \SavedRecipe.title) private var saved: [SavedRecipe]
    @Query(filter: #Predicate<PantryItem> { !$0.isUsedUp }) private var items: [PantryItem]
    var guestAllergies: [String] = []
    private var recipes: [RecipeIdea] {
        guard let profile = profiles.first else { return [] }
        return RecipeFoundation.candidates(items: items, profile: profile, logs: logs, saved: saved).filter {
            AllergenGuard.violations(in: [$0.title] + $0.ingredients + $0.steps, allergies: guestAllergies).isEmpty
        }
    }
    var body: some View {
        List {
            Section {
                Text("Saved recipes and original basic methods are available without generating a new answer. Check package labels and recipe notes before cooking.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if recipes.isEmpty {
                ContentUnavailableView("No matching recipes", systemImage: "book.closed",
                    description: Text("Add a recipe that fits your household and any guests' allergies to your recipe book."))
            }
            ForEach(Array(recipes.enumerated()), id: \.offset) { _, recipe in
                NavigationLink {
                    RecipeDetailView(title: recipe.title, summary: recipe.summary, minutes: recipe.minutes,
                        servings: recipe.servings, ingredients: recipe.ingredients, steps: recipe.steps)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        RecipeRow(title: recipe.title, summary: recipe.summary, minutes: recipe.minutes)
                        let missing = KitchenStock.plan(recipe.ingredients, items: items).filter { !$0.covered }.count
                        Text(missing == 0 ? "Recorded amounts cover the ingredients" : "\(missing) ingredients to buy or check")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .gardePage()
        .navigationTitle("Cooking foundation")
    }
}
