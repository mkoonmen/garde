import Foundation

/// Helpers that turn a long, marketing-heavy order email into just the part that matters
/// (item lines + totals), so the on-device model sees the items instead of headers and footers.
enum EmailReceipt {
    static let price = /\$\s?\d{1,4}(?:,\d{3})*\.\d{2}|\b\d{1,4}\.\d{2}\b/

    struct Focus { var text: String; var total: Double?; var priceLines: Int }

    static func focus(_ body: String) -> Focus {
        let lines = body.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let noise = ["unsubscribe", "privacy", "terms", "copyright", "©", "view in browser", "download the app", "follow us",
                     "customer service", "help center", "manage preferences", "rewards balance", "this email", "all rights reserved"]
        var keep = IndexSet()
        var priceLines = 0
        for (i, l) in lines.enumerated() where l.contains(price) {
            let low = l.lowercased()
            if noise.contains(where: low.contains) { continue }
            priceLines += 1
            // An item line often has its name or quantity on the line above.
            keep.insert(integersIn: max(0, i - 2)...min(lines.count - 1, i))
        }
        // If the email lists items with no prices (some order confirmations), keep "Qty" style lines too.
        for (i, l) in lines.enumerated() where l.lowercased().contains(/\bqty\b|\bquantity\b|\b\d+\s*x\b/) { keep.insert(i) }
        let text = keep.map { lines[$0] }.joined(separator: "\n")
        return Focus(text: text.isEmpty ? String(body.prefix(3000)) : text, total: total(in: lines), priceLines: priceLines)
    }

    /// The order total: the last "total" line that isn't a subtotal/savings line.
    static func total(in lines: [String]) -> Double? {
        var found: Double?
        for (i, l) in lines.enumerated() {
            let low = l.lowercased()
            guard low.contains("total"), !low.contains("subtotal"), !low.contains("sub-total"), !low.contains("saving"), !low.contains("items total") else { continue }
            let candidates = [l] + (i + 1 < lines.count ? [lines[i + 1]] : [])
            for c in candidates {
                if let m = c.firstMatch(of: price) {
                    let v = Double(String(m.0).replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces))
                    if let v, v > 0 { found = v; break }
                }
            }
        }
        return found
    }

    static func chunks(_ text: String, size: Int) -> [String] {
        var out: [String] = [], cur = ""
        for line in text.split(separator: "\n") {
            if cur.count + line.count > size, !cur.isEmpty { out.append(cur); cur = "" }
            cur += line + "\n"
        }
        if !cur.isEmpty { out.append(cur) }
        return Array(out.prefix(6))
    }

    static func dedupe(_ items: [ParsedItem]) -> [ParsedItem] {
        var seen: [String: Int] = [:], out: [ParsedItem] = []
        for i in items {
            let k = ShoppingBrain.key(i.name)
            guard !k.isEmpty else { continue }
            if let idx = seen[k] {
                if out[idx].price == nil { out[idx].price = i.price }   // same item seen in two chunks
            } else { seen[k] = out.count; out.append(i) }
        }
        return out
    }

    /// Drops obvious non-food (paper towels, shampoo, batteries…) that slip into grocery orders.
    static func isFood(_ i: ParsedItem) -> Bool {
        let n = i.name.lowercased()
        let nonFood = ["paper towel", "toilet", "tissue", "shampoo", "conditioner", "detergent", "soap", "toothpaste", "diaper", "wipes",
                       "battery", "batteries", "trash bag", "foil", "plastic wrap", "deodorant", "lotion", "razor", "cleaner", "bleach",
                       "sponge", "light bulb", "charger", "cable", "vitamin", "medicine", "bag fee", "delivery fee", "service fee", "tip", "gift card"]
        return !nonFood.contains(where: n.contains)
    }

    /// Store name from the sender/subject ("Instacart <...>", "Your Stop & Shop order").
    static func store(from: String, subject: String) -> String? {
        let t = (from + " " + subject).lowercased()
        let known: [(String, String)] = [("instacart", "Instacart"), ("whole foods", "Whole Foods"), ("wholefoods", "Whole Foods"),
            ("stop & shop", "Stop & Shop"), ("stopandshop", "Stop & Shop"), ("king kullen", "King Kullen"), ("wegmans", "Wegmans"),
            ("costco", "Costco"), ("trader joe", "Trader Joe's"), ("shoprite", "ShopRite"), ("bjs", "BJ's Wholesale Club"),
            ("bj's", "BJ's Wholesale Club"), ("walmart", "Walmart"), ("target", "Target"), ("amazon fresh", "Amazon Fresh"),
            ("freshdirect", "FreshDirect"), ("aldi", "ALDI"), ("lidl", "Lidl"), ("peapod", "Peapod")]
        return known.first { t.contains($0.0) }?.1
    }
}
