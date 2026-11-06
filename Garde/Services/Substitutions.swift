import Foundation

/// Classic kitchen swaps that work without the AI (instant, offline). Checked against allergies by the caller.
enum Substitutions {
    static let table: [(keys: [String], options: [String], note: String)] = [
        (["buttermilk"], ["1 cup milk + 1 tbsp lemon juice or white vinegar, rest 5 min", "3/4 cup plain yogurt + 1/4 cup milk"], "Same tang and tenderness."),
        (["heavy cream", "whipping cream"], ["3/4 cup milk + 1/4 cup melted butter (for cooking, not whipping)", "Half-and-half (thinner sauce)"], "Won't whip; fine in sauces and soups."),
        (["sour cream"], ["Plain Greek yogurt, same amount"], "Slightly tangier; add off the heat so it doesn't split."),
        (["egg", "eggs"], ["1 tbsp ground flax + 3 tbsp water per egg (baking)", "1/4 cup applesauce per egg (sweet bakes)"], "Works for binding, not for whites-only recipes."),
        (["butter"], ["Olive oil at 3/4 the amount (sautéing)", "Ghee, same amount"], "Baking texture changes with oil."),
        (["brown sugar"], ["1 cup white sugar + 1 tbsp molasses"], "Same moisture and flavor."),
        (["shallot", "shallots"], ["Red onion + a little garlic, same amount"], "A touch sharper."),
        (["fresh herbs", "parsley", "cilantro", "basil"], ["1 tsp dried per 1 tbsp fresh (add earlier)"], "Dried is stronger; cook it in, don't sprinkle at the end."),
        (["lemon juice"], ["Lime juice, same amount", "White wine vinegar at half the amount"], "Keeps the brightness."),
        (["white wine"], ["Chicken broth + 1 tsp white wine vinegar per cup"], "For deglazing and sauces."),
        (["red wine"], ["Beef broth + 1 tsp red wine vinegar per cup"], "For braises."),
        (["breadcrumbs", "panko"], ["Crushed crackers or cornflakes", "Rolled oats pulsed in a blender"], "Still crisps."),
        (["cornstarch"], ["2 tbsp flour per 1 tbsp cornstarch"], "Cook a minute longer to lose the raw-flour taste."),
        (["soy sauce"], ["Tamari (gluten-free)", "Coconut aminos (less salty)"], "Same umami."),
        (["mayonnaise", "mayo"], ["Plain Greek yogurt + squeeze of lemon"], "Lighter, tangier."),
        (["chicken broth", "chicken stock"], ["Water + 1 bouillon cube per cup", "Vegetable broth"], "Taste for salt."),
        (["parmesan"], ["Pecorino Romano (saltier)", "Grana Padano"], "Use a little less pecorino."),
        (["ricotta"], ["Cottage cheese, blended smooth"], "Drain if it's watery."),
        (["honey"], ["Maple syrup, same amount"], "Slightly thinner."),
        (["baking powder"], ["1/4 tsp baking soda + 1/2 tsp cream of tartar per 1 tsp"], "Mix right before using."),
        (["pine nuts"], ["Toasted sunflower or pumpkin seeds", "Toasted almonds, chopped"], "Nut-free option first."),
        (["walnuts", "pecans"], ["Toasted almonds or hazelnuts", "Toasted pumpkin seeds"], "Same crunch."),
    ]

    static func offline(for line: String) -> (options: [String], note: String)? {
        let food = RecipeScaler.foodName(line).lowercased()
        let words = food.split { !$0.isLetter }.map(String.init)
        // Single-word keys must be the food itself ("butter"), not part of another food ("peanut butter", "egg noodles").
        let modifiers: Set<String> = ["peanut", "almond", "apple", "cocoa", "nut", "cashew", "sunflower", "shea", "seed", "coconut", "oat", "soy"]
        func matchesKey(_ k: String) -> Bool {
            if k.contains(" ") { return food.contains(k) }
            guard let last = words.last, last == k || last == k + "s" else { return false }
            return !words.dropLast().contains(where: modifiers.contains)
        }
        guard let hit = table.first(where: { e in e.keys.contains(where: matchesKey) }) else { return nil }
        return (hit.options, hit.note)
    }
}
