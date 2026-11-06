import Foundation

/// One-line technique tips for cook mode, matched from the step text. Offline, no AI.
enum ChefTips {
    static let table: [(words: [String], tip: String)] = [
        (["sear", "brown the"], "Pat it dry, get the pan hot, and don't move it until it releases on its own."),
        (["caramelize"], "Low and slow: 30+ minutes, a pinch of salt, stir only now and then."),
        (["sauté", "saute"], "Hot pan, then oil, then food. Don't crowd it or it steams."),
        (["deglaze"], "Scrape up the brown bits with a wooden spoon. That's the flavor."),
        (["rest"], "Resting keeps the juices in. Tent loosely with foil."),
        (["whisk"], "A damp towel under the bowl keeps it from spinning."),
        (["fold"], "Cut down the middle, sweep along the bottom, turn the bowl. Stop when just combined."),
        (["boil", "pasta"], "Salt the water like the sea. Save a cup of pasta water before draining."),
        (["simmer"], "Small, lazy bubbles. A rolling boil makes sauces split and meat tough."),
        (["roast"], "Spread it out on the pan; space is what gives you browning."),
        (["mince", "garlic"], "Smash the clove with the flat of the knife first; the skin slips off."),
        (["dice", "chop"], "Curl your fingertips under and guide the blade with your knuckles."),
        (["season", "salt"], "Season in layers and taste as you go."),
        (["emulsify", "vinaigrette"], "Add the oil in a thin stream while whisking."),
        (["thicken", "reduce"], "It thickens more as it cools. Stop just before it looks right."),
        (["temper", "eggs"], "Whisk a little of the hot liquid into the eggs first so they don't scramble."),
        (["fry", "oil"], "Oil is ready when a wooden spoon handle bubbles steadily. Never leave it."),
        (["internal temperature", "thermometer", "165", "145"], "Chicken 165°F, pork 145°F, steak medium-rare 130°F. Check the thickest part."),
        (["grill"], "Clean, oiled grates. Let it release before flipping."),
        (["bake", "oven"], "Most ovens run hot or cold; an oven thermometer is a cheap fix."),
    ]

    static func tip(for step: String) -> String? {
        let s = step.lowercased()
        return table.first { $0.words.contains { s.contains($0) } }?.tip
    }
}
