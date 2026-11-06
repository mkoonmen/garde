import Foundation
import AuthenticationServices
import SwiftData
import Security
import CryptoKit
import UIKit

/// Pulls grocery receipts out of Gmail (read-only) and turns them into pantry items.
/// Sign-in is Google OAuth with PKCE; the refresh token lives in the iPhone Keychain.
/// Email text is parsed by the on-device model — message contents never go anywhere but Google → this phone.
@MainActor
final class GmailImporter: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GmailImporter()

    /// Garde's own Google sign-in client (built into the app, so anyone can connect their Gmail with no setup).
    /// It's a public identifier, not a secret. An override can still be set for testing.
    var clientID: String {
        if let o = UserDefaults.standard.string(forKey: "gmail.clientID"), !o.isEmpty { return o }
        return Bundle.main.object(forInfoDictionaryKey: "GardeGoogleClientID") as? String ?? ""
    }
    // MARK: Accounts (several Gmail accounts, plus iCloud Mail or other IMAP mailboxes)

    struct MailAccount: Codable, Identifiable, Hashable {
        enum Kind: String, Codable { case gmail, imap }
        var id: String = UUID().uuidString
        var kind: Kind
        var email: String
        var host: String = ""          // IMAP server, e.g. imap.mail.me.com
        var secretKey: String { "mail.secret." + id }   // Keychain: Gmail refresh token or IMAP app-specific password
        var label: String { kind == .gmail ? "Gmail" : host.contains("me.com") ? "iCloud Mail" : host.contains("yahoo") ? "Yahoo Mail" : "Email" }
    }

    var accounts: [MailAccount] {
        get {
            var list = (UserDefaults.standard.data(forKey: "mail.accounts")).flatMap { try? JSONDecoder().decode([MailAccount].self, from: $0) } ?? []
            // Move the single Gmail connection from older versions into the list.
            if list.isEmpty, let old = Keychain.get("gmail.refresh") {
                let a = MailAccount(kind: .gmail, email: UserDefaults.standard.string(forKey: "gmail.email") ?? "Gmail")
                Keychain.set(old, for: a.secretKey); Keychain.delete("gmail.refresh")
                list = [a]
                UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: "mail.accounts")
            }
            return list
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "mail.accounts") }
    }
    var isSignedIn: Bool { !accounts.isEmpty }

    func remove(_ account: MailAccount) {
        Keychain.delete(account.secretKey)
        accounts.removeAll { $0.id == account.id }
    }

    /// Adds an iCloud (or other IMAP) mailbox after checking the password works.
    func addIMAP(email: String, password: String, host: String) async throws {
        let e = email.trimmingCharacters(in: .whitespaces).lowercased()
        let pw = password.trimmingCharacters(in: .whitespaces)
        let client = IMAPClient(host: host)
        try await client.connect()
        // iCloud accepts the full address or just the name before the @.
        do { try await client.login(user: e, password: pw) }
        catch { if host.contains("me.com"), let short = e.split(separator: "@").first { try await client.login(user: String(short), password: pw) } else { throw error } }
        await client.logout()
        var list = accounts.filter { !($0.kind == .imap && $0.email == e) }
        let a = MailAccount(kind: .imap, email: e, host: host)
        Keychain.set(pw, for: a.secretKey)
        list.append(a)
        accounts = list
    }
    private var authSession: ASWebAuthenticationSession?   // must be retained while the sheet is up
    private var isImporting = false

    /// Searches that catch grocery receipts and orders.
    /// Every order and receipt from grocery stores and big-box stores over the past year.
    /// Shipping/delivery status emails are skipped because they repeat the original order.
    static let stores = ["target", "walmart", "costco", "bjs", "\"bj's\"", "kingkullen", "\"king kullen\"", "stopandshop", "\"stop & shop\"",
                         "finefare", "\"fine fare\"", "wholefoods", "wholefoodsmarket", "\"whole foods\"", "sprouts", "traderjoes", "\"trader joe's\"",
                         "wegmans", "shoprite", "aldi", "lidl", "publix", "kroger", "safeway", "acme", "giant", "foodtown", "keyfood", "\"key food\"",
                         "c-town", "ctown", "\"western beef\"", "\"h mart\"", "hmart", "samsclub", "\"sam's club\"", "instacart", "freshdirect",
                         "peapod", "amazon", "\"amazon fresh\"", "doordash", "ubereats", "uber", "grubhub", "seamless", "caviar", "postmates", "gopuff", "thrivemarket", "\"thrive market\"",
                         "harristeeter", "\"harris teeter\"", "foodlion", "\"food lion\"", "heb", "meijer", "hannaford", "pricechopper", "shopwell"]
    static let defaultQuery = """
    newer_than:1y -subject:(shipped OR "out for delivery" OR "on its way" OR "has been delivered" OR "was delivered" OR "arriving" \
    OR return OR refund OR survey OR "rate your" OR "review your" OR "weekly ad" OR "% off" OR sale) \
    (from:(\(stores.joined(separator: " OR "))) OR subject:(receipt OR "your order" OR "order confirmation" OR "order #" OR "e-receipt" OR "digital receipt")) \
    (receipt OR order OR total)
    """
    /// Email ids already handled, oldest first (kept in order so trimming drops the oldest, not random ones).
    private var processed = ProcessedIDs()
    struct ProcessedIDs {
        private var list: [String]
        private var set: Set<String>
        init() { list = UserDefaults.standard.stringArray(forKey: "gmail.processed") ?? []; set = Set(list) }
        func contains(_ id: String) -> Bool { set.contains(id) }
        mutating func insert(_ id: String) {
            guard !set.contains(id) else { return }
            set.insert(id); list.append(id)
            if list.count > 5000 { list.removeFirst(list.count - 5000); set = Set(list) }
            if list.count % 25 == 0 { save() }
        }
        func save() { UserDefaults.standard.set(list, forKey: "gmail.processed") }
        mutating func reset() { list = []; set = []; UserDefaults.standard.removeObject(forKey: "gmail.processed") }
    }

    enum GmailError: LocalizedError {
        case noClientID, auth(String), api(String)
        var errorDescription: String? {
            switch self {
            case .noClientID: "Gmail sign-in isn't set up in this build yet."
            case .auth(let m): "Google sign-in failed: \(m)"
            case .api(let m): "Gmail error: \(m)"
            }
        }
    }

    // MARK: Sign in

    func signIn() async throws {
        guard !clientID.isEmpty else { throw GmailError.noClientID }
        let scheme = "com.googleusercontent.apps." + clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        let redirect = scheme + ":/oauth2redirect"
        let verifier = PKCE.verifier()
        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "https://www.googleapis.com/auth/gmail.readonly"),
            .init(name: "code_challenge", value: PKCE.challenge(verifier)),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
        ]
        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(url: comps.url!, callback: .customScheme(scheme)) { url, err in
                if let url { cont.resume(returning: url) } else { cont.resume(throwing: GmailError.auth(err?.localizedDescription ?? "cancelled")) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            if !session.start() { cont.resume(throwing: GmailError.auth("couldn't open Google sign-in")) }
        }
        authSession = nil
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw GmailError.auth("no code returned")
        }
        let tokens = try await tokenRequest(["code": code, "code_verifier": verifier, "redirect_uri": redirect, "grant_type": "authorization_code"])
        guard let refresh = tokens["refresh_token"] as? String else { throw GmailError.auth("no refresh token") }
        // Which Gmail is this? (So a second account is added, not mixed up with the first.)
        var email = "Gmail"
        if let access = tokens["access_token"] as? String,
           let profile = try? await get(URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/profile")!, token: access),
           let address = profile["emailAddress"] as? String { email = address.lowercased() }
        var list = accounts
        if let old = list.first(where: { $0.kind == .gmail && $0.email == email }) { Keychain.delete(old.secretKey); list.removeAll { $0.id == old.id } }
        let a = MailAccount(kind: .gmail, email: email)
        Keychain.set(refresh, for: a.secretKey)
        list.append(a)
        accounts = list
    }

    /// Disconnects every mailbox.
    func signOut() { accounts.forEach { Keychain.delete($0.secretKey) }; accounts = []; Keychain.delete("gmail.refresh") }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }

    // MARK: Import

    struct ImportReport { var receipts = 0, items = 0, skipped = 0, emails = 0, takeout = 0, waiting = 0; var problems: [String] = [] }

    /// Imports receipt emails not seen before from every connected mailbox. `progress(done, total)` is called as each email is read.
    @discardableResult
    func importNew(context: ModelContext, progress: ((Int, Int) -> Void)? = nil) async throws -> ImportReport {
        var report = ImportReport()
        if isImporting { throw GmailError.api("An import is already running. Try again in a moment.") }
        let mailboxes = accounts
        guard !mailboxes.isEmpty else { return report }
        isImporting = true
        defer { isImporting = false; processed.save() }
        processed = ProcessedIDs()   // pick up any reset done elsewhere
        // Emails skipped by older, stricter or buggier readers get one more look with this version's rules
        // (receipts already imported are recognized by their id and not duplicated).
        if !UserDefaults.standard.bool(forKey: "mail.recheck.v292") {
            processed.reset()
            UserDefaults.standard.set(true, forKey: "mail.recheck.v292")
        }

        let known = Set(((try? context.fetch(FetchDescriptor<Receipt>())) ?? []).compactMap(\.sourceID))
            .union(((try? context.fetch(FetchDescriptor<TakeoutOrder>())) ?? []).compactMap(\.sourceID))
        var run = Run(brainReady: ChefAI().state == .available,
                      existingTakeout: (try? context.fetch(FetchDescriptor<TakeoutOrder>())) ?? [])
        var problems: [String] = []
        for account in mailboxes {
            do {
                switch account.kind {
                case .gmail: try await importGmail(account, known: known, context: context, run: &run, report: &report, progress: progress)
                case .imap: try await importIMAP(account, known: known, context: context, run: &run, report: &report, progress: progress)
                }
            } catch {
                problems.append("\(account.email): \(error.localizedDescription)")
            }
        }
        UserDefaults.standard.set(Date.now, forKey: "gmail.lastSync")
        // One mailbox failing shouldn't hide what the others imported; only throw if nothing worked.
        if !problems.isEmpty && report.emails == 0 { throw GmailError.api(problems.joined(separator: "\n")) }
        report.problems = problems
        return report
    }

    @MainActor private struct Run { var brainReady: Bool; var existingTakeout: [TakeoutOrder]; let chef = ChefAI() }

    private func importGmail(_ account: MailAccount, known: Set<String>, context: ModelContext, run: inout Run,
                             report: inout ImportReport, progress: ((Int, Int) -> Void)?) async throws {
        guard !clientID.isEmpty, let refresh = Keychain.get(account.secretKey) else { return }
        let tokens = try await tokenRequest(["refresh_token": refresh, "grant_type": "refresh_token"])
        guard let access = tokens["access_token"] as? String else { throw GmailError.auth("Please reconnect this Gmail (Google sign-ins in testing expire weekly).") }
        let query = UserDefaults.standard.string(forKey: "gmail.query").flatMap { $0.isEmpty ? nil : $0 } ?? Self.defaultQuery
        var ids: [String] = []
        var page: String?
        repeat {
            var list = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
            list.queryItems = [.init(name: "q", value: query), .init(name: "maxResults", value: "100")] + (page.map { [.init(name: "pageToken", value: $0)] } ?? [])
            let json = try await get(list.url!, token: access)
            ids += ((json["messages"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }
            page = json["nextPageToken"] as? String
        } while page != nil && ids.count < 1500
        let fresh = ids.filter { !processed.contains($0) && !known.contains("gmail:" + $0) }
        report.emails += fresh.count
        for (n, id) in fresh.enumerated() {
            progress?(n + 1, fresh.count)
            guard let msg = try? await get(URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)?format=full")!, token: access) else { continue }
            let (subject, from, date, body) = Self.extract(msg)
            await handle(processedKey: id, sourceID: "gmail:" + id, subject: subject, from: from, date: date, body: body,
                         context: context, run: &run, report: &report)
        }
    }

    /// iCloud Mail / IMAP: read headers for the past year, keep only store and delivery senders, then read those bodies.
    private func importIMAP(_ account: MailAccount, known: Set<String>, context: ModelContext, run: inout Run,
                            report: inout ImportReport, progress: ((Int, Int) -> Void)?) async throws {
        guard let password = Keychain.get(account.secretKey) else { return }
        let client = IMAPClient(host: account.host)
        try await client.connect()
        do { try await client.login(user: account.email, password: password) }
        catch {
            guard account.host.contains("me.com"), let short = account.email.split(separator: "@").first else { throw error }
            try await client.login(user: String(short), password: password)
        }
        try await client.select("INBOX")
        let since = Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .now
        let all = try await client.uids(since: since).suffix(4000)
        let prefix = "imap:\(account.id):"
        let unseen = all.filter { !processed.contains(prefix + String($0)) && !known.contains(prefix + String($0)) }
        // Headers in batches; only receipts from stores and delivery apps are worth opening.
        var wanted: [(uid: Int, from: String, subject: String, date: Date)] = []
        for start in stride(from: 0, to: unseen.count, by: 150) {
            let batch = Array(unseen[unseen.index(unseen.startIndex, offsetBy: start)..<unseen.index(unseen.startIndex, offsetBy: min(start + 150, unseen.count))])
            for h in try await client.headers(batch) {
                let relevant = Takeout.service(from: h.from, subject: h.subject) != nil || EmailReceipt.groceryStore(from: h.from, subject: h.subject) != nil
                if relevant && !EmailReceipt.isNotice(h.subject) { wanted.append(h) } else { processed.insert(prefix + String(h.uid)) }
            }
        }
        report.emails += wanted.count
        for (n, h) in wanted.enumerated() {
            progress?(n + 1, wanted.count)
            guard let raw = try? await client.message(h.uid) else { continue }
            await handle(processedKey: prefix + String(h.uid), sourceID: prefix + String(h.uid), subject: h.subject, from: h.from,
                         date: h.date, body: MIMEParser.bodyText(raw), context: context, run: &run, report: &report)
        }
        await client.logout()
    }

    /// What happened to each email in the latest imports (newest first), so "why isn't my receipt here?" has an answer.
    struct LogLine: Codable, Identifiable { var id = UUID(); var date = Date(); var from: String; var subject: String; var outcome: String }
    static var log: [LogLine] {
        get { (UserDefaults.standard.data(forKey: "mail.log")).flatMap { try? JSONDecoder().decode([LogLine].self, from: $0) } ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(Array(newValue.prefix(300))), forKey: "mail.log") }
    }
    private func log(_ from: String, _ subject: String, _ outcome: String) {
        Self.log.insert(LogLine(from: Self.storeName(from: from), subject: subject, outcome: outcome), at: 0)
    }

    /// Turns one email into a grocery receipt, a takeout order, or nothing.
    private func handle(processedKey id: String, sourceID: String, subject: String, from: String, date: Date, body: String,
                        context: ModelContext, run: inout Run, report: inout ImportReport) async {
        // Restaurant delivery receipts become takeout history (for cooking inspiration), not groceries.
        if let service = Takeout.service(from: from, subject: subject) {
            // Status emails ("delivered", "rate your order") would duplicate the same meal.
            if EmailReceipt.isNotice(subject) { log(from, subject, "Skipped: delivery/status update"); report.skipped += 1; processed.insert(id); return }
            // Without the AI, leave it unread so it's picked up once the model is ready.
            guard run.brainReady else { log(from, subject, "Waiting for Apple Intelligence"); report.waiting += 1; return }
            if let order = await Takeout.parse(subject: subject, from: from, body: body, date: date, service: service) {
                // The same meal often arrives as a confirmation and a receipt: keep one.
                let day = Calendar.current.startOfDay(for: date)
                let dupes = !order.dishes.isEmpty && run.existingTakeout.contains {
                    Calendar.current.startOfDay(for: $0.date) == day && $0.restaurant.caseInsensitiveCompare(order.restaurant) == .orderedSame
                        && Set($0.dishes.map { $0.lowercased() }) == Set(order.dishes.map { $0.lowercased() })
                        && ($0.total == nil || order.total == nil || abs(($0.total ?? 0) - (order.total ?? 0)) < 0.01)
                }
                if dupes { log(from, subject, "Skipped: same meal already saved"); report.skipped += 1; processed.insert(id); return }
                order.sourceID = sourceID
                context.insert(order)
                run.existingTakeout.append(order)
                report.takeout += 1; log(from, subject, "Takeout: \(order.restaurant)")
            } else { report.skipped += 1; log(from, subject, "Skipped: couldn't read the order") }
            processed.insert(id); try? context.save()
            return
        }
        // Only real grocery stores become grocery receipts; everything else (software, subscriptions, shipping notices) is ignored.
        guard let knownStore = EmailReceipt.groceryStore(from: from, subject: subject),
              !EmailReceipt.isNotice(subject) else { log(from, subject, EmailReceipt.isNotice(subject) ? "Skipped: shipping/status email" : "Skipped: not from a grocery store Garde knows"); report.skipped += 1; processed.insert(id); return }
        let focus = EmailReceipt.focus(body)
        guard focus.priceLines >= 1 else { log(from, subject, "Skipped: no prices in the email"); report.skipped += 1; processed.insert(id); return }   // no prices = not a receipt

        // Read in chunks so long receipts fit the on-device model, then merge.
        var items: [ParsedItem] = []
        var aiTotal: Double?
        for chunk in EmailReceipt.chunks(focus.text, size: 2200) {
            let parsed = await run.chef.parseScan(text: "From: \(from)\nSubject: \(subject)\n\n" + chunk, labels: [])
            items += parsed.items
            if aiTotal == nil { aiTotal = parsed.total }
        }
        items = EmailReceipt.dedupe(items).filter { EmailReceipt.isFood($0) }
        // A real receipt has a total, or at least a few food lines. "1 item, no total" is an order update.
        guard !items.isEmpty, (focus.total ?? aiTotal) != nil || items.count >= 3 else { log(from, subject, items.isEmpty ? "Skipped: no food items found" : "Skipped: no total and under 3 items"); report.skipped += 1; processed.insert(id); return }

        let store = knownStore
        let receipt = Receipt(store: store, date: date, total: focus.total ?? aiTotal, rawText: "From: \(from)\nSubject: \(subject)\n\n" + focus.text)
        receipt.sourceID = sourceID
        context.insert(receipt)
        for p in items {
            let loc = ShelfLife.defaultLocation(for: p.category, name: p.name)
            let item = PantryItem(name: p.name, category: p.category, location: loc, quantity: p.quantity, unit: p.unit,
                                  purchaseDate: date, expirationDate: p.printedExpiration ?? ShelfLife.estimatedExpiration(name: p.name, category: p.category, in: loc, from: date),
                                  expirationIsEstimated: p.printedExpiration == nil, price: p.price, store: store)
            // Old orders: food bought weeks ago is probably gone; count it as history, not current stock.
            if date < .now.addingTimeInterval(-21 * 86_400) { item.isUsedUp = true; item.usedUpDate = date }
            item.receipt = receipt
            context.insert(item)
        }
        if date >= .now.addingTimeInterval(-21 * 86_400) { ShoppingBrain.checkOff(names: items.map(\.name), context: context) }
        log(from, subject, "Imported \(Plural.items(items.count))"); report.receipts += 1; report.items += items.count
        processed.insert(id)
        try? context.save()
    }

    /// Deletes everything imported from Gmail and reads the past year again with the current reader.
    func reimport(context: ModelContext, progress: ((Int, Int) -> Void)? = nil) async throws -> ImportReport {
        if isImporting { throw GmailError.api("An import is already running. Try again in a moment.") }
        let fromMail: (String?) -> Bool = { $0?.hasPrefix("gmail:") == true || $0?.hasPrefix("imap:") == true }
        for r in (try? context.fetch(FetchDescriptor<Receipt>())) ?? [] where fromMail(r.sourceID) {
            (r.items ?? []).forEach(context.delete)
            context.delete(r)
        }
        for t in (try? context.fetch(FetchDescriptor<TakeoutOrder>())) ?? [] where fromMail(t.sourceID) { context.delete(t) }
        processed.reset()
        try? context.save()
        return try await importNew(context: context, progress: progress)
    }

    // MARK: Helpers

    private func tokenRequest(_ params: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var all = params; all["client_id"] = clientID
        req.httpBody = all.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if let err = json["error"] as? String { throw GmailError.auth(err) }
        return json
    }

    private func get(_ url: URL, token: String) async throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw GmailError.api(String(data: data, encoding: .utf8)?.prefix(200).description ?? "unknown") }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    static func extract(_ msg: [String: Any]) -> (String, String, Date, String) {
        let payload = msg["payload"] as? [String: Any] ?? [:]
        let headers = (payload["headers"] as? [[String: Any]]) ?? []
        func header(_ n: String) -> String { headers.first { ($0["name"] as? String)?.lowercased() == n }?["value"] as? String ?? "" }
        let ms = Double(msg["internalDate"] as? String ?? "") ?? Date.now.timeIntervalSince1970 * 1000
        var plain = "", html = ""
        func walk(_ part: [String: Any]) {
            let mime = part["mimeType"] as? String ?? ""
            if let data = (part["body"] as? [String: Any])?["data"] as? String, let text = base64url(data) {
                if mime == "text/plain" { plain += text } else if mime == "text/html" { html += text }
            }
            ((part["parts"] as? [[String: Any]]) ?? []).forEach(walk)
        }
        walk(payload)
        let body = plain.isEmpty ? stripHTML(html) : plain
        return (header("subject"), header("from"), Date(timeIntervalSince1970: ms / 1000), body)
    }

    static func base64url(_ s: String) -> String? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        return Data(base64Encoded: b).map { String(data: $0, encoding: .utf8) ?? String(data: $0, encoding: .isoLatin1) ?? String(decoding: $0, as: UTF8.self) }
    }

    nonisolated static func stripHTML(_ html: String) -> String {
        html.replacing(/<style[^>]*>[\s\S]*?<\/style>/.ignoresCase(), with: "")
            .replacing(/<script[^>]*>[\s\S]*?<\/script>/.ignoresCase(), with: "")
            .replacing(/<br\s*\/?>|<\/(p|div|tr|li|h\d|table)>/.ignoresCase(), with: "\n")
            .replacing(/<\/t[dh]>/.ignoresCase(), with: "  ")
            .replacing(/<[^>]+>/, with: " ")
            .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#36;", with: "$").replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&quot;", with: "\"")
            .replacing(/&zwnj;|&#8203;|\u{200B}|\u{200C}|\u{034F}/, with: "")
            .replacing(/[ \t]+/, with: " ")
            .replacing(/\n\s*\n+/, with: "\n")
    }

    static func storeName(from: String) -> String {
        from.split(separator: "<").first.map { $0.trimmingCharacters(in: .whitespaces.union(.init(charactersIn: "\""))) } ?? "Online order"
    }
}

// MARK: - PKCE + Keychain


enum PKCE {
    static func verifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URL
    }
    static func challenge(_ verifier: String) -> String { Data(SHA256.hash(data: Data(verifier.utf8))).base64URL }
}

extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

enum Keychain {
    static func set(_ value: String, for key: String) {
        delete(key)
        SecItemAdd([kSecClass: kSecClassGenericPassword, kSecAttrAccount: key, kSecValueData: Data(value.utf8),
                    kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock] as CFDictionary, nil)
    }
    static func get(_ key: String) -> String? {
        var out: AnyObject?
        let status = SecItemCopyMatching([kSecClass: kSecClassGenericPassword, kSecAttrAccount: key, kSecReturnData: true,
                                          kSecMatchLimit: kSecMatchLimitOne] as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func delete(_ key: String) {
        SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrAccount: key] as CFDictionary)
    }
}
