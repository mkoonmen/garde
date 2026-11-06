import Foundation
import SwiftData

/// Original, fixed kitchen methods. Times include preparation; actual doneness is checked while cooking.
enum RecipeFoundation {
    static let temperatureSource = URL(string: "https://www.fda.gov/food/buy-store-serve-safe-food/safe-food-handling")!
    static let basics: [RecipeIdea] = [
        RecipeIdea(title: "Tomato garlic pasta", summary: "A pantry pasta with a quick tomato sauce.", minutes: 30, servings: 2,
                   ingredients: ["180 g pasta", "300 g tomato", "2 cloves garlic", "1 tbsp olive oil", "1/4 tsp salt", "1/4 tsp black pepper"],
                   steps: ["Prepare for 5 minutes: chop the tomato and garlic and bring a saucepan of water to a boil.", "Cook the pasta according to its package, usually 10 minutes. Save a cup of its cooking water before draining.", "Meanwhile, warm olive oil in a skillet. Add garlic for 1 minute, then tomato, salt and black pepper. Simmer 12 minutes.", "Toss the drained pasta with the sauce for 2 minutes, adding a splash of the reserved water if needed."], usesFromKitchen: []),
        RecipeIdea(title: "Spinach scrambled eggs", summary: "Soft eggs and greens for an easy supper.", minutes: 15, servings: 2,
                   ingredients: ["4 eggs", "100 g spinach", "1 tbsp butter", "1/4 tsp salt", "1/4 tsp black pepper"],
                   steps: ["Prepare for 3 minutes: wash spinach and beat eggs with salt and black pepper.", "Melt butter in a skillet over medium heat and wilt spinach for 2 minutes.", "Lower the heat and add eggs. Stir gently for about 5 minutes until firm with no runny egg remaining. Serve immediately."], usesFromKitchen: []),
        RecipeIdea(title: "Lemon chickpea skillet", summary: "Warm chickpeas and spinach with bright lemon.", minutes: 20, servings: 2,
                   ingredients: ["400 g cooked chickpeas", "100 g spinach", "1 lemon", "2 cloves garlic", "1 tbsp olive oil", "1/4 tsp salt"],
                   steps: ["Prepare for 5 minutes: drain and rinse cooked chickpeas, wash spinach, chop garlic and cut lemon.", "Warm olive oil in a skillet. Soften garlic over medium heat for 1 minute.", "Add chickpeas, salt and 2 tablespoons water. Simmer 7 minutes, then stir in spinach for 2 minutes.", "Squeeze in lemon to taste and serve warm."], usesFromKitchen: []),
        RecipeIdea(title: "Chicken and broccoli skillet", summary: "A simple skillet dinner with a lemon finish.", minutes: 35, servings: 2,
                   ingredients: ["350 g chicken breast", "250 g broccoli", "1 lemon", "1 tbsp olive oil", "1/4 tsp salt", "1/4 tsp black pepper"],
                   steps: ["Prepare for 10 minutes: cut broccoli into florets, cut chicken into even bite-size pieces, and keep raw-chicken tools separate from ready-to-eat food.", "Heat olive oil in a skillet over medium-high heat. Season chicken with salt and black pepper and cook for about 10 minutes, turning regularly.", "Add broccoli and 3 tablespoons water. Cover and cook 7 minutes. Check chicken with a thermometer: every piece must reach 165°F (74°C). Continue cooking if needed.", "Uncover, squeeze lemon over the skillet to taste, and serve."], usesFromKitchen: []),
        RecipeIdea(title: "Roasted salmon and broccoli", summary: "A small sheet-pan dinner with lemon.", minutes: 35, servings: 2,
                   ingredients: ["300 g salmon", "250 g broccoli", "1 lemon", "1 tbsp olive oil", "1/4 tsp salt", "1/4 tsp black pepper"],
                   steps: ["Allow 10 minutes to heat the oven to 425°F (220°C), cut broccoli into small florets and line a baking tray.", "Toss broccoli with half the olive oil, salt and black pepper. Roast for 8 minutes.", "Add salmon, brush with remaining olive oil, and add lemon slices. Roast about 12 minutes, checking the thickest part of salmon reaches 145°F (63°C). Continue cooking if needed."], usesFromKitchen: []),
        RecipeIdea(title: "Garlic butter rice", summary: "A simple rice side with a savory finish.", minutes: 35, servings: 2,
                   ingredients: ["150 g rice", "300 ml water", "1 tbsp butter", "2 cloves garlic", "1/4 tsp salt"],
                   steps: ["Prepare for 5 minutes: rinse rice and mince garlic. Check the rice package for its recommended water ratio and adjust water if needed.", "Melt butter in a saucepan and soften garlic over low heat for 1 minute.", "Add rice, water and salt. Bring to a boil, cover and simmer gently according to the package, usually 15 minutes for white rice.", "Turn off the heat and rest covered for 10 minutes. Fluff before serving."], usesFromKitchen: [])
    ]

    struct Check {
        var errors: [String] = []
        var notes: [String] = []
        var valid: Bool { errors.isEmpty }
    }

    static func check(_ recipe: RecipeIdea) -> Check {
        var result = Check()
        if recipe.title.trimmingCharacters(in: .whitespaces).isEmpty || recipe.ingredients.isEmpty || recipe.steps.isEmpty { result.errors.append("Recipe is incomplete.") }
        if !(1...20).contains(recipe.servings) { result.errors.append("Check the serving count.") }
        if !(5...360).contains(recipe.minutes) { result.errors.append("Check the total time.") }
        let foods = recipe.ingredients.map { FoodIdentity.ingredient(RecipeScaler.foodName($0)) }
        for line in recipe.ingredients {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { result.errors.append("An ingredient is blank.") }
            if RecipeScaler.leadingAmount(line) == nil && !line.lowercased().contains("to taste") { result.notes.append("Confirm amount: " + line) }
        }
        for step in recipe.steps {
            if let seconds = CookVoice.duration(in: step), seconds > recipe.minutes * 60 { result.errors.append("A step exceeds the total cooking time.") }
            for (food, aliases) in FoodIdentity.aliases where aliases.contains(where: { FoodIdentity.contains($0, in: step) }) {
                // Ignore shorter names contained within another explicitly named ingredient.
                let namedInList = foods.contains { FoodIdentity.matches(food, $0) || FoodIdentity.matches($0, food) || FoodIdentity.contains(food, in: $0) }
                let basic = ["olive oil", "water", "salt", "pepper"].contains(food)
                if !namedInList && !basic { result.notes.append("The directions mention " + food + "; confirm it is in the ingredients.") }
            }
        }
        if recipe.steps.contains(where: { $0.lowercased().contains("overnight") }) && recipe.minutes < 480 { result.errors.append("Overnight preparation needs a separate advance-preparation recipe.") }
        result.notes = Array(Set(result.notes)).sorted()
        return result
    }

    @MainActor
    static func candidates(items: [PantryItem], profile: KitchenProfile, logs: [CookLog], saved: [SavedRecipe] = []) -> [RecipeIdea] {
        let savedIdeas = saved.map { RecipeIdea(title: $0.title, summary: $0.summary, minutes: $0.minutes, servings: $0.servings, ingredients: $0.ingredients, steps: $0.steps, usesFromKitchen: []) }
        let never = Set(logs.filter(\.neverAgain).map { $0.title.lowercased() })
        var seen: Set<String> = []
        return (savedIdeas + basics).filter { recipe in
            seen.insert(recipe.title.lowercased()).inserted && !never.contains(recipe.title.lowercased()) && check(recipe).valid &&
            AllergenGuard.violations(in: [recipe.title] + recipe.ingredients + recipe.steps, allergies: profile.allergies).isEmpty &&
            !profile.dislikes.contains(where: { dislike in recipe.ingredients.contains { FoodIdentity.contains(dislike, in: $0) } })
        }
    }

    @MainActor
    static func fallback(items: [PantryItem], profile: KitchenProfile, logs: [CookLog], request: ChefAI.RecipeRequest) -> [RecipeIdea] {
        let saved = (try? GardeStore.container.mainContext.fetch(FetchDescriptor<SavedRecipe>())) ?? []
        return candidates(items: items, profile: profile, logs: logs, saved: saved)
            .filter { $0.minutes <= request.maxMinutes && (!request.noShopping || KitchenStock.plan($0.ingredients, items: items).allSatisfy(\.covered)) }
            .sorted { KitchenStock.plan($0.ingredients, items: items).filter { !$0.covered }.count < KitchenStock.plan($1.ingredients, items: items).filter { !$0.covered }.count }
    }
}
