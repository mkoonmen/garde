import Foundation
import FoundationModels
import UIKit

/// Turns anything shared to Garde into a recipe:
///  1. Recipe websites: reads the page's built-in recipe data (schema.org JSON-LD), so nothing is guessed.
///  2. TikTok / YouTube: reads the public title/caption, then the chef writes it up.
///  3. Instagram, other pages, pasted text: the chef reads the text.
///  4. Photos of cookbook pages / screenshots: read on-device (OCR), then the chef writes it up.
/// Every result is checked against allergies before it's shown.
@MainActor
enum RecipeImporter {
    struct Imported {
        var recipe: RecipeIdea
        var source: String
        var allergens: [String]
        var missing: [String]
    }

    enum ImportError: LocalizedError {
        case nothingFound, chefOffline
        var errorDescription: String? {
            switch self {
            case .nothingFound: "Couldn't find a recipe in that."
            case .chefOffline: "The chef needs Apple Intelligence (or the downloaded model) to read this one."
            }
        }
    }

    static func importItem(_ item: InboxItem, profile: KitchenProfile?, pantry: [PantryItem]) async throws -> Imported {
        var recipe: RecipeIdea?
        var source = item.url ?? "Shared text"
        var context = item.text ?? ""

        if let s = item.url, let url = URL(string: s) {
            if let host = url.host?.lowercased(), host.contains("tiktok") || host.contains("youtube") || host.contains("youtu.be") {
                if let caption = await oEmbedTitle(for: url) { context = caption + "\n" + context }
            } else if let html = await fetch(url) {
                recipe = jsonLDRecipe(in: html)
                if recipe == nil { context = String(pageText(html).prefix(6000)) + "\n" + context }
            }
            source = url.host ?? s
        }
        if recipe == nil, let data = RecipeInbox.imageData(for: item), let img = UIImage(data: data) {
            let ocr = (try? await TextRecognizer.recognizeText(in: img)) ?? ""
            context = ocr + "\n" + context
            source = item.url == nil ? "Photo" : source
        }
        if recipe == nil {
            let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw ImportError.nothingFound }
            recipe = try await writeUp(trimmed)
        }
        guard let r = recipe, !r.title.isEmpty, !r.ingredients.isEmpty else { throw ImportError.nothingFound }

        let allergens = AllergenGuard.violations(in: [r.title] + r.ingredients + r.steps, allergies: profile?.allergies ?? [])
        let stocked = pantry.filter { !$0.isUsedUp }
        let missing = r.ingredients.filter { line in
            !stocked.contains { ShoppingBrain.appears($0.name, in: line) } && !Nutrition.isZero(line)
        }
        return Imported(recipe: r, source: source, allergens: allergens, missing: missing)
    }

    // MARK: Chef write-up (when there's no structured recipe)

    static func writeUp(_ text: String) async throws -> RecipeIdea {
        guard ChefEngine.shared.usingLocal || SystemLanguageModel.default.availability == .available else { throw ImportError.chefOffline }
        let session = ChefEngine.shared.session(instructions: """
        You turn social media captions, video titles, web pages and cookbook text into a clean home recipe.
        Keep the original dish. If amounts or steps are missing, fill them in sensibly for a home cook.
        If there is clearly no dish described, return an empty title.
        """)
        return try await session.respond(to: String(text.prefix(5000)), generating: RecipeIdea.self).content
    }

    // MARK: Web helpers

    static func fetch(_ url: URL) async -> String? {
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                     forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    static func oEmbedTitle(for url: URL) async -> String? {
        let host = url.host?.lowercased() ?? ""
        let endpoint = host.contains("tiktok") ? "https://www.tiktok.com/oembed?url=" : "https://www.youtube.com/oembed?format=json&url="
        guard let enc = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let api = URL(string: endpoint + enc),
              let (data, _) = try? await URLSession.shared.data(from: api),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return [json["title"] as? String, json["author_name"].map { "by \($0)" }].compactMap { $0 }.joined(separator: " ")
    }

    /// Reads schema.org Recipe data that most recipe sites embed.
    static func jsonLDRecipe(in html: String) -> RecipeIdea? {
        for m in html.matches(of: /<script[^>]*application\/ld\+json[^>]*>([\s\S]*?)<\/script>/.ignoresCase()) {
            guard let data = String(m.1).data(using: .utf8),
                  let any = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let r = findRecipe(any) { return r }
        }
        return nil
    }

    private static func findRecipe(_ any: Any) -> RecipeIdea? {
        if let arr = any as? [Any] { return arr.lazy.compactMap(findRecipe).first }
        guard let obj = any as? [String: Any] else { return nil }
        if let graph = obj["@graph"] { if let r = findRecipe(graph) { return r } }
        let type = obj["@type"]
        let isRecipe = (type as? String) == "Recipe" || ((type as? [String])?.contains("Recipe") ?? false)
        guard isRecipe else { return nil }
        let title = clean(obj["name"] as? String ?? "")
        let ingredients = (obj["recipeIngredient"] as? [String] ?? []).map(clean)
        var steps: [String] = []
        func walk(_ x: Any?) {
            if let s = x as? String { steps += s.components(separatedBy: "\n").map(clean).filter { !$0.isEmpty } }
            else if let a = x as? [Any] { a.forEach(walk) }
            else if let d = x as? [String: Any] {
                if let t = d["text"] as? String { steps.append(clean(t)) }
                if let items = d["itemListElement"] { walk(items) }
            }
        }
        walk(obj["recipeInstructions"])
        let minutes = isoMinutes(obj["totalTime"] as? String) ?? isoMinutes(obj["cookTime"] as? String) ?? 30
        let servings: Int = {
            if let s = obj["recipeYield"] as? String { return Int(s.filter(\.isNumber).prefix(2)) ?? 4 }
            if let a = obj["recipeYield"] as? [Any], let s = a.first as? String { return Int(s.filter(\.isNumber).prefix(2)) ?? 4 }
            if let n = obj["recipeYield"] as? Int { return n }
            return 4
        }()
        let summary = clean(obj["description"] as? String ?? "")
        return RecipeIdea(title: title, summary: summary.isEmpty ? title : String(summary.prefix(200)), minutes: minutes,
                          servings: max(1, servings), ingredients: ingredients, steps: steps, usesFromKitchen: [])
    }

    static func isoMinutes(_ s: String?) -> Int? {
        guard let s, let m = s.firstMatch(of: /P(?:\d+D)?T?(?:(\d+)H)?(?:(\d+)M)?/) else { return nil }
        let total = (Int(m.1 ?? "") ?? 0) * 60 + (Int(m.2 ?? "") ?? 0)
        return total > 0 ? total : nil
    }

    static func clean(_ s: String) -> String {
        s.replacing(/<[^>]+>/, with: "")
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func pageText(_ html: String) -> String { GmailImporter.stripHTML(html) }
}
