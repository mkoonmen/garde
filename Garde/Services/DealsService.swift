import Foundation

/// This week's grocery-store circulars near your ZIP (Stop & Shop, ALDI, Lidl, Wegmans, Target, Costco…),
/// read from Flipp, the service behind most US weekly ads. Steps:
///   1. list the flyers for the ZIP, keep the grocery ones that are running now
///   2. download each flyer's items (name, brand, price, dates)
///   3. match them on the phone against your list and what's running low; browse/search the rest
/// Flipp isn't an official public API, so all network code is in this file and easy to swap.
/// Only the ZIP code is sent; nothing about your kitchen leaves the phone.
@MainActor
@Observable
final class DealsService {
    static let shared = DealsService()

    struct Deal: Identifiable, Hashable, Codable {
        var id: String
        var name: String
        var brand: String
        var store: String
        var price: Double?
        var discountPercent: Int?
        var validTo: Date?
        var priceText: String {
            guard let price else { return discountPercent.map { "\($0)% off" } ?? "On sale" }
            let p = price.formatted(.currency(code: "USD"))
            return discountPercent.map { "\(p) (\($0)% off)" } ?? p
        }
    }

    struct Flyer: Hashable, Codable { var id: Int; var store: String; var validTo: Date? }

    /// Every item in this week's grocery ads.
    var all: [Deal] = []
    /// The subset matching your list / running-low items, keyed by the matched name.
    var matches: [String: [Deal]] = [:]
    private var currentTerms: [String] = []
    var flyers: [Flyer] = []
    var lastRefresh: Date? = UserDefaults.standard.object(forKey: "deals.last") as? Date
    var refreshing = false
    var error: String?

    // Stored (not computed) so SwiftUI sees changes; each one is saved as it changes.
    // No default ZIP for testers; the owner's (developer options unlocked) defaults to Remsenburg.
    var zip: String = UserDefaults.standard.string(forKey: "deals.zip") ?? (DeveloperMode.unlocked ? "11960" : "") {
        didSet {
            UserDefaults.standard.set(zip.filter(\.isNumber), forKey: "deals.zip")
            UserDefaults.standard.removeObject(forKey: "deals.last")
            lastRefresh = nil
        }
    }
    /// Stores to hide (everything else in the grocery category is shown).
    var hiddenStores: [String] = UserDefaults.standard.stringArray(forKey: "deals.hidden") ?? [] {
        didSet { UserDefaults.standard.set(hiddenStores, forKey: "deals.hidden") }
    }
    var enabled: Bool = UserDefaults.standard.object(forKey: "deals.enabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(enabled, forKey: "deals.enabled") }
    }

    /// What to look for on sale: everything on the list, plus things in the kitchen that run out within 3 days.
    static func terms(list: [ShoppingItem], pantry: [PantryItem]) -> [String] {
        list.filter { !$0.isChecked }.map(\.name) + pantry.filter { !$0.isUsedUp && ($0.daysLeft ?? 99) <= 3 }.map(\.name)
    }

    var stores: [String] { Array(Set(flyers.map(\.store))).sorted() }
    var visible: [Deal] { all.filter { !hiddenStores.contains($0.store) } }
    var matchedDeals: [Deal] {
        var seen = Set<String>()
        return matches.values.flatMap { $0 }.filter { !hiddenStores.contains($0.store) && seen.insert($0.id).inserted }
            .sorted { ($0.discountPercent ?? 0, -($0.price ?? 999)) > ($1.discountPercent ?? 0, -($1.price ?? 999)) }
    }

    private init() { loadCache() }

    /// Downloads this week's ads (if stale or ZIP changed) and re-matches against `terms`.
    func refresh(terms: [String], force: Bool = false) async {
        currentTerms = terms
        guard enabled else { return }
        guard zip.count == 5 else { error = "Add your 5-digit ZIP code in Deals settings to see sales near you."; return }
        error = nil
        let stale = force || all.isEmpty || (lastRefresh ?? .distantPast) < .now.addingTimeInterval(-6 * 3600)
        if stale {
            refreshing = true
            defer { refreshing = false }
            let z = zip
            guard let list = await Self.groceryFlyers(zip: z) else { error = "Couldn't reach the weekly ads. Try again in a bit."; return }
            guard !list.isEmpty else { error = "No grocery ads found for \(z)."; all = []; flyers = []; return }
            var items: [Deal] = []
            await withTaskGroup(of: [Deal].self) { group in
                for f in list.prefix(12) { group.addTask { await Self.items(in: f) } }
                for await chunk in group { items += chunk }
            }
            flyers = list
            all = items.sorted { $0.name < $1.name }
            lastRefresh = .now
            UserDefaults.standard.set(lastRefresh, forKey: "deals.last")
            saveCache()
        }
        match(currentTerms)
    }

    /// Matches deals to names (list items, running-low items). Runs on the phone, no network.
    func match(_ terms: [String]) {
        currentTerms = terms
        var out: [String: [Deal]] = [:]
        for t in Set(terms.map(ShoppingBrain.key)) where t.count >= 3 {
            let hits = all.filter { ShoppingBrain.appears(t, in: $0.name + " " + $0.brand) }
            if !hits.isEmpty { out[t] = Array(hits.sorted { ($0.price ?? 999) < ($1.price ?? 999) }.prefix(4)) }
        }
        matches = out
    }

    func deals(for name: String) -> [Deal] { (matches[ShoppingBrain.key(name)] ?? []).filter { !hiddenStores.contains($0.store) } }

    func search(_ q: String) -> [Deal] {
        let k = q.lowercased().trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty else { return visible }
        return visible.filter { ($0.name + " " + $0.brand + " " + $0.store).lowercased().contains(k) }
    }

    /// Short text for the AI planner: what's on sale right now.
    var plannerHint: String {
        let pool = matchedDeals.isEmpty ? Array(visible.filter { $0.price != nil }.prefix(15)) : Array(matchedDeals.prefix(15))
        return pool.map { "\($0.name) at \($0.store) (\($0.priceText))" }.joined(separator: "; ")
    }

    // MARK: Flipp

    nonisolated static func get(_ url: URL) async -> Any? {
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Garde-iOS/2.2 (personal app)", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    nonisolated static func date(_ any: Any?) -> Date? {
        guard let s = any as? String else { return nil }
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withFullDate]
        return f.date(from: String(s.prefix(10)))
    }

    nonisolated static func groceryFlyers(zip: String) async -> [Flyer]? {
        guard let url = URL(string: "https://backflipp.wishabi.com/flipp/flyers?locale=en-us&postal_code=\(zip)"),
              let json = await get(url) else { return nil }
        let raw = (json as? [[String: Any]]) ?? ((json as? [String: Any])?["flyers"] as? [[String: Any]]) ?? []
        let now = Date.now
        return raw.compactMap { f -> Flyer? in
            let cats: String = {
                if let a = f["categories"] as? [String] { return a.joined(separator: ",") }
                if let s = f["categories"] as? String { return s }
                if let a = f["categories_csv"] as? String { return a }
                return ""
            }().lowercased()
            guard cats.contains("grocer"), let id = f["id"] as? Int else { return nil }
            let from = date(f["valid_from"]) ?? .distantPast
            let to = date(f["valid_to"])
            guard from <= now.addingTimeInterval(86_400), (to ?? .distantFuture) >= now else { return nil }
            let store = (f["merchant"] as? String) ?? (f["merchant_name"] as? String) ?? "Store"
            return Flyer(id: id, store: store, validTo: to)
        }
    }

    nonisolated static func items(in flyer: Flyer) async -> [Deal] {
        guard let url = URL(string: "https://backflipp.wishabi.com/flipp/flyers/\(flyer.id)"),
              let json = await get(url) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { i -> Deal? in
            let name = (i["name"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            // Skip internal placeholders like "NewItem_ChikFilA_WK4526_SS_Digital".
            guard !name.isEmpty, !name.contains("_") else { return nil }
            let price: Double? = (i["price"] as? Double) ?? (i["price"] as? String).flatMap { Double($0.filter { $0.isNumber || $0 == "." }) }
            let discount = (i["discount"] as? Int) ?? (i["discount"] as? Double).map(Int.init)
            guard price != nil || discount != nil else { return nil }
            return Deal(id: "\(i["id"] ?? UUID().uuidString)", name: name, brand: i["brand"] as? String ?? "", store: flyer.store,
                        price: price, discountPercent: discount, validTo: date(i["valid_to"]) ?? flyer.validTo)
        }
    }

    // MARK: Cache (instant + offline)

    private struct Cache: Codable { var all: [Deal]; var flyers: [Flyer]; var zip: String }
    private var cacheURL: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("deals-v2.json") }
    private func saveCache() { try? JSONEncoder().encode(Cache(all: all, flyers: flyers, zip: zip)).write(to: cacheURL) }
    private func loadCache() {
        guard let d = try? Data(contentsOf: cacheURL), let c = try? JSONDecoder().decode(Cache.self, from: d), c.zip == zip else { return }
        all = c.all.filter { ($0.validTo ?? .distantFuture) > .now }
        flyers = c.flyers
    }
}
