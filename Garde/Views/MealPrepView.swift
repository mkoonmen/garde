import SwiftUI
import SwiftData

/// Sunday meal prep: a couple of batch dishes that cover the week, one efficient session, and the shopping list.
struct MealPrepView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<PantryItem> { !$0.isUsedUp }) private var items: [PantryItem]
    @Query private var profiles: [KitchenProfile]
    @Query private var logs: [CookLog]
    @State private var meals = 5
    @State private var people = 1
    @State private var focus = ""
    @State private var plan: MealPrep?
    @State private var working = false
    @State private var message: String?
    @State private var added = false
    @State private var saved: Set<String> = []

    private let focuses = ["High protein", "Lunches for work", "Low carb", "Comfort food", "Freezer-friendly", "Budget"]

    var body: some View {
        List { Group {
            Section {
                Stepper("\(meals) meals", value: $meals, in: 2...14)
                Stepper("For \(people) \(people == 1 ? "person" : "people")", value: $people, in: 1...8)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack { ForEach(focuses, id: \.self) { f in Button(f) { focus = focus == f ? "" : f }.buttonStyle(.bordered).tint(focus == f ? Theme.copper : .secondary) } }
                }
                Button { Task { await make() } } label: {
                    HStack { Spacer(); if working { ProgressView() } else { Label("Plan my prep", systemImage: "takeoutbag.and.cup.and.straw") }; Spacer() }
                }.disabled(working)
            } footer: { Text("Built around what expires first. Checked against your allergies.") }
            if let message { Section { Text(message).foregroundStyle(.orange) } }
            if let plan {
                ForEach(Array(plan.dishes.enumerated()), id: \.offset) { _, d in
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(d.name).gardeHeading(.headline)
                            Text("\(d.portions) portions · \(d.storage)").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(d.ingredients, id: \.self) { Text("• \($0)").font(.subheadline) }
                        Button(saved.contains(d.name) ? "Saved" : "Save recipe", systemImage: saved.contains(d.name) ? "checkmark" : "bookmark") {
                            // Keep only the session steps that are about this dish (fall back to all of them).
                            let words = ShoppingBrain.words(d.name).filter { $0.count > 3 }
                            let own = plan.session.filter { step in words.contains { step.lowercased().contains($0) } }
                            context.insert(SavedRecipe(title: d.name, summary: "Meal prep · \(d.portions) portions · \(d.storage)", minutes: 60,
                                                       servings: d.portions, ingredients: d.ingredients, steps: own.count >= 2 ? own : plan.session))
                            saved.insert(d.name)
                        }.disabled(saved.contains(d.name))
                    }
                }
                Section("Prep session") {
                    ForEach(Array(plan.session.enumerated()), id: \.offset) { i, s in
                        HStack(alignment: .top) { Text("\(i + 1)").foregroundStyle(Theme.copper).frame(width: 22); Text(s) }
                    }
                }
                Section("To buy") {
                    ForEach(plan.shoppingList, id: \.self) { Text("• \($0)") }
                    Button(added ? "Added to your list" : "Add all to shopping list", systemImage: added ? "checkmark" : "cart.badge.plus") {
                        ShoppingBrain.add(needToBuy: plan.shoppingList.map { RecipeScaler.foodName($0).capitalized }, for: "Meal prep", day: .now, context: context)
                        added = true
                    }.disabled(added || plan.shoppingList.isEmpty)
                }
            }
        }.listRowBackground(RowGlass()) }
        .gardePage()
        .navigationTitle("Meal prep")
    }

    private func make() async {
        guard let profile = profiles.first else { message = "Set up your kitchen profile first."; return }
        let chef = ChefAI()
        if case .unavailable(let why) = chef.state { message = why; return }
        working = true; message = nil; added = false; saved = []
        defer { working = false }
        for _ in 0..<2 {
            do {
                if let p = try await chef.mealPrep(meals: meals, people: people, focus: focus, items: items, profile: profile, logs: logs) {
                    withAnimation { plan = p }; return
                }
            } catch { message = "The chef got stuck: \(error.localizedDescription)"; return }
        }
        message = "Every plan included one of your allergens, so it was thrown out. Try another focus."
    }
}
