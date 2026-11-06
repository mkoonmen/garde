import Foundation

/// Recipe identity is separate from the branded product printed on a receipt.
enum FoodIdentity {
    static let aliases: [(String, [String])] = [
        ("garlic bread", ["garlic bread"]), ("banana bread", ["banana bread"]),
        ("bread crumbs", ["bread crumb", "breadcrumb", "panko"]),
        ("potato chips", ["potato chip"]), ("tortilla chips", ["tortilla chip"]),
        ("tomato soup", ["tomato soup"]), ("chicken soup", ["chicken soup"]),
        ("chocolate milk", ["chocolate milk"]), ("egg roll", ["egg roll"]),
        ("almond flour", ["almond flour"]), ("coconut flour", ["coconut flour"]),
        ("onion dip", ["onion dip"]), ("spinach dip", ["spinach dip"]),
        ("lemon juice", ["lemon juice"]), ("lime juice", ["lime juice"]),
        ("rice milk", ["rice milk"]), ("hemp milk", ["hemp milk"]), ("pea milk", ["pea milk"]), ("macadamia milk", ["macadamia milk"]),
        ("evaporated milk", ["evaporated milk"]), ("condensed milk", ["condensed milk"]),
        ("egg white", ["egg white"]), ("egg yolk", ["egg yolk"]), ("egg noodles", ["egg noodle"]),
        ("garlic powder", ["garlic powder"]), ("onion powder", ["onion powder"]),
        ("chicken nuggets", ["chicken nugget"]),
        ("almond milk", ["almond milk", "silk almond"]), ("oat milk", ["oat milk"]),
        ("soy milk", ["soy milk"]), ("coconut milk", ["coconut milk"]), ("cashew milk", ["cashew milk"]),
        ("coffee creamer", ["creamer"]), ("heavy cream", ["heavy cream", "whipping cream"]),
        ("half and half", ["half and half", "half & half"]), ("sour cream", ["sour cream"]),
        ("cream cheese", ["cream cheese"]), ("peanut butter", ["peanut butter"]),
        ("almond butter", ["almond butter"]), ("cocoa powder", ["cocoa powder"]),
        ("chicken broth", ["chicken broth", "chicken stock"]), ("vegetable broth", ["vegetable broth", "vegetable stock"]),
        ("beef broth", ["beef broth", "beef stock"]), ("pasta sauce", ["pasta sauce", "marinara"]),
        ("soy sauce", ["soy sauce"]), ("fish sauce", ["fish sauce"]), ("oyster sauce", ["oyster sauce"]),
        ("tomato paste", ["tomato paste"]), ("chicken breast", ["chicken breast"]),
        ("chicken thigh", ["chicken thigh"]), ("ground beef", ["ground beef"]),
        ("ground turkey", ["ground turkey"]), ("olive oil", ["olive oil"]),
        ("brown sugar", ["brown sugar"]), ("powdered sugar", ["powdered sugar", "confectioner sugar"]),
        ("milk", ["whole milk", "homogenized milk", "skim milk", "2% milk", "milk"]),
        ("butter", ["butter"]), ("egg", ["egg"]), ("flour", ["flour"]),
        ("rice", ["rice"]), ("pasta", ["pasta", "spaghetti", "penne", "rigatoni", "linguine"]),
        ("chicken", ["chicken"]), ("salmon", ["salmon"]), ("shrimp", ["shrimp", "prawn"]),
        ("onion", ["onion"]), ("garlic", ["garlic"]), ("lemon", ["lemon"]),
        ("lime", ["lime"]), ("spinach", ["spinach"]), ("broccoli", ["broccoli"]),
        ("tomato", ["tomato"]), ("potato", ["potato"]), ("carrot", ["carrot"]),
        ("parmesan", ["parmesan"]), ("cheddar", ["cheddar"]), ("mozzarella", ["mozzarella"]),
        ("bread", ["bread"]), ("yogurt", ["yogurt"]), ("black bean", ["black bean"]),
        ("chickpea", ["chickpea", "garbanzo"]), ("lentil", ["lentil"])
    ]

    static func words(_ name: String) -> [String] {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split { !$0.isLetter && !$0.isNumber }.map {
                let word = String($0)
                let irregular = ["tomatoes": "tomato", "potatoes": "potato", "leaves": "leaf", "loaves": "loaf", "berries": "berry"]
                if let singular = irregular[word] { return singular }
                return word.count > 3 && word.hasSuffix("s") && !word.hasSuffix("ss") ? String(word.dropLast()) : word
            }
    }

    static func contains(_ phrase: String, in name: String) -> Bool {
        (" " + words(name).joined(separator: " ") + " ").contains(" " + words(phrase).joined(separator: " ") + " ")
    }

    private static let normalizedAliases = aliases.map { key, names in
        (key, names.map { " " + words($0).joined(separator: " ") + " " })
    }

    static func ingredient(_ name: String) -> String {
        let tokens = words(name)
        let normalized = " " + tokens.joined(separator: " ") + " "
        if tokens == ["cream"] { return "heavy cream" }
        if normalized.contains(" milk chocolate ") { return "milk chocolate" }
        if normalized.contains(" ice cream ") { return "ice cream" }
        for (key, names) in normalizedAliases where names.contains(where: { normalized.contains($0) }) { return key }
        let ignored: Set<String> = ["organic", "fresh", "large", "small", "medium", "boneless", "skinless", "chopped", "diced", "sliced", "minced", "of"]
        return tokens.filter { !ignored.contains($0) && !$0.allSatisfy(\.isNumber) }.joined(separator: " ")
    }

    static func matches(_ requested: String, _ available: String) -> Bool {
        let need = ingredient(requested), have = ingredient(available)
        guard !need.isEmpty, !have.isEmpty else { return false }
        if need == have { return true }
        // These explicitly generic ingredient requests accept a particular cut or variety.
        if need == "chicken" { return ["chicken breast", "chicken thigh"].contains(have) }
        return false
    }

    static func productKey(_ name: String, barcode: String? = nil) -> String {
        if let barcode, !barcode.isEmpty { return "barcode/" + barcode }
        // Preserve brands, varieties and package sizes for product matching.
        return words(name).joined(separator: " ")
    }
}
