import Foundation

/// Looks up a product by barcode in Open Food Facts (free, open database).
/// This is the one scan feature that needs internet; the barcode number is all that's sent.
enum BarcodeLookup {
    struct Product {
        var name: String
        var brand: String
        var size: String
        var category: FoodCategory
        var allergens: [String]
    }

    @MainActor private static var cache: [String: Product] = [:]

    @MainActor
    static func lookup(_ code: String) async -> Product? {
        if let hit = cache[code] { return hit }
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=product_name,brands,quantity,categories_tags,allergens_tags,traces_tags") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 6)
        req.setValue("Garde-iOS/1.0 (personal app)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["status"] as? Int) == 1,
              let p = json["product"] as? [String: Any] else { return nil }
        let name = (p["product_name"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        // An unnamed product can still carry allergen data: keep it so the scan can warn (you type the name).
        let hasAllergenData = !((p["allergens_tags"] as? [String]) ?? []).isEmpty || !((p["traces_tags"] as? [String]) ?? []).isEmpty
        guard !name.isEmpty || hasAllergenData else { return nil }
        let tags = (p["categories_tags"] as? [String]) ?? []
        let product = Product(name: name,
                              brand: (p["brands"] as? String ?? "").components(separatedBy: ",").first ?? "",
                              size: p["quantity"] as? String ?? "",
                              category: category(from: tags, name: name),
                              allergens: ((p["allergens_tags"] as? [String]) ?? []).map { $0.replacingOccurrences(of: "en:", with: "") }
                                + ((p["traces_tags"] as? [String]) ?? []).map { "may contain " + $0.replacingOccurrences(of: "en:", with: "") })
        cache[code] = product
        return product
    }

    static func category(from tags: [String], name: String) -> FoodCategory {
        let t = tags.joined(separator: " ")
        let pairs: [(String, FoodCategory)] = [("cheeses", .cheese), ("seafood", .seafood), ("fishes", .seafood), ("poultr", .poultry),
                                               ("meats", .meat), ("eggs", .eggs), ("dairies", .dairy), ("milks", .dairy), ("yogurts", .dairy),
                                               ("frozen", .frozen), ("breads", .bakery), ("fruits", .fruit), ("vegetables", .produce),
                                               ("cereals", .grains), ("pastas", .grains), ("rices", .grains), ("canned", .canned),
                                               ("sauces", .condiments), ("condiments", .condiments), ("beverages", .beverages), ("snacks", .snacks)]
        if let hit = pairs.first(where: { t.contains($0.0) }) { return hit.1 }
        return ShoppingBrain.guessCategory(name)
    }
}
