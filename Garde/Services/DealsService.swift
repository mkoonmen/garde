import Foundation

/// Weekly sale prices near you, matched to your shopping list and what's running low.
/// Source: Flipp's public weekly-circular search (the data behind most US grocery flyers).
/// It's an unofficial endpoint, so it's isolated here behind one function and can be swapped for another source.
/// Only the search word and ZIP code are sent; nothing about your kitchen leaves the phone.
@MainActor
@Observable
final class DealsService {
    static let shared = DealsService()

    struct Deal: Identifiable, Hashable, Codable {
        var id: String
        var name: String
        var store: String
        var price: Double?
        var wasPrice: Double?
        var priceText: String     // "2 for $5", "$3.99/lb" etc.
        var validTo: Date?
        var matchedTerm: String   // what on your list/pantry it matched
        var savings: Double? { (wasPrice != nil && price != nil) ? max(0, wasPrice! - price!) : nil }
    }

    var deals: [Deal] = []
    var lastRefresh: Date? = UserDefaults.standard.object(forKey: "deals.last") as? Date
    var refreshing = false
    var error: String?

    var zip: String {
        // No default ZIP for testers; the owner's (developer options unlocked) defaults to Remsenburg.
        get { UserDefaults.standard.string(forKey: "deals.zip") ?? (DeveloperMode.unlocked ? "11960" : "") }
        set { UserDefaults.standard.set(newValue, forKey: "deals.zip") }
    }
    /// Stores to include (empty = any grocery store found).
    var stores: [String] {
        get { UserDefaults.standard.stringArray(forKey: "deals.stores") ?? ["Stop & Shop", "King Kullen", "ShopRite", "Costco", "BJ's", "Whole Foods", "Trader Joe's", "Target", "Walmart", "Wegmans", "Aldi"] }
        set { UserDefaults.standard.set(newValue, forKey: "deals.stores") }
    }
    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "deals.enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "deals.enabled") }
    }

    private init() { loadCache() }

    /// Looks up each term (list items first, then things running low), keeps the best deal per term.
    func refresh(terms rawTerms: [String]) async {
        guard enabled else { return }
        guard !zip.isEmpty else { error = "Add your ZIP code (List → All deals → Settings) to see sales near you."; return }
        let terms = Array(NSOrderedSet(array: rawTerms.map(ShoppingBrain.key).filter { $0.count >= 3 })).compactMap { $0 as? String }.prefix(25)
        guard !terms.isEmpty else { deals = []; return }
        refreshing = true; error = nil
        defer { refreshing = false }
        var found: [Deal] = []
        var failures = 0
        let z = zip
        await withTaskGroup(of: [Deal]?.self) { group in
            for term in terms { group.addTask { await Self.search(term: term, zip: z) } }
            for await r in group { if let r { found += r } else { failures += 1 } }
        }
        if failures == terms.count { error = "Couldn't reach the weekly ads right now."; return }
        let allowed = stores.map { $0.lowercased() }
        let filtered = found.filter { d in allowed.isEmpty || allowed.contains { d.store.lowercased().contains($0) || $0.contains(d.store.lowercased()) } }
        // Best (cheapest) per term + store.
        var best: [String: Deal] = [:]
        for d in filtered {
            let k = d.matchedTerm + "|" + d.store
            if let cur = best[k], (cur.price ?? .infinity) <= (d.price ?? .infinity) { continue }
            best[k] = d
        }
        deals = best.values.sorted { ($0.savings ?? 0) > ($1.savings ?? 0) }
        lastRefresh = .now
        UserDefaults.standard.set(lastRefresh, forKey: "deals.last")
        saveCache()
    }

    /// Deals for one shopping-list or pantry name.
    func deals(for name: String) -> [Deal] {
        let k = ShoppingBrain.key(name)
        return deals.filter { $0.matchedTerm == k }
    }

    // MARK: Source

    nonisolated static func search(term: String, zip: String) async -> [Deal]? {
        var c = URLComponents(string: "https://backflipp.wishabi.com/flipp/items/search")!
        c.queryItems = [.init(name: "locale", value: "en-us"), .init(name: "postal_code", value: zip), .init(name: "q", value: term)]
        var req = URLRequest(url: c.url!, timeoutInterval: 10)
        req.setValue("Garde-iOS/2.0 (personal app)", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let iso = ISO8601DateFormatter()
        let flyer = (json["items"] as? [[String: Any]]) ?? []
        let words = term.split(separator: " ").map(String.init)
        return flyer.compactMap { i -> Deal? in
            let name = (i["name"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let store = i["merchant_name"] as? String ?? i["merchant"] as? String ?? ""
            guard !name.isEmpty, !store.isEmpty else { return nil }
            // The product name must actually contain the thing we searched for.
            let lname = name.lowercased()
            guard words.allSatisfy({ lname.contains($0) || ($0.hasSuffix("s") && lname.contains(String($0.dropLast()))) }) else { return nil }
            let price = (i["current_price"] as? Double) ?? (i["current_price"] as? String).flatMap(Double.init)
            let was = (i["original_price"] as? Double) ?? (i["original_price"] as? String).flatMap(Double.init)
            let text = [i["pre_price_text"] as? String, price.map { String(format: "$%.2f", $0) }, i["post_price_text"] as? String, i["sale_story"] as? String]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            let id = "\(i["flyer_item_id"] ?? i["id"] ?? UUID().uuidString)"
            return Deal(id: id, name: name, store: store, price: price, wasPrice: was, priceText: text.isEmpty ? "On sale" : text,
                        validTo: (i["valid_to"] as? String).flatMap { iso.date(from: $0) }, matchedTerm: term)
        }
    }

    // MARK: Cache (so deals show instantly and offline)

    private var cacheURL: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("deals.json") }
    private func saveCache() { try? JSONEncoder().encode(deals).write(to: cacheURL) }
    private func loadCache() {
        guard let d = try? Data(contentsOf: cacheURL), let saved = try? JSONDecoder().decode([Deal].self, from: d) else { return }
        deals = saved.filter { ($0.validTo ?? .distantFuture) > .now }
    }

    /// Short text for the AI planner: what's on sale right now.
    var plannerHint: String {
        deals.prefix(15).map { "\($0.name) at \($0.store) (\($0.priceText))" }.joined(separator: "; ")
    }
}
