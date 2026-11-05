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

    /// Google Cloud "iOS" OAuth client ID, e.g. 1234-abc.apps.googleusercontent.com (set in More → Gmail).
    var clientID: String { UserDefaults.standard.string(forKey: "gmail.clientID") ?? "" }
    var isSignedIn: Bool { Keychain.get("gmail.refresh") != nil }
    private var authSession: ASWebAuthenticationSession?   // must be retained while the sheet is up
    private var isImporting = false

    /// Searches that catch grocery receipts and orders.
    static let defaultQuery = """
    newer_than:45d (subject:(receipt OR "your order" OR "order confirmation" OR "e-receipt" OR delivered) \
    (instacart OR "whole foods" OR "stop & shop" OR "king kullen" OR wegmans OR costco OR "trader joe" OR shoprite \
    OR walmart OR target OR "amazon fresh" OR freshdirect OR peapod OR "bj's" OR grocery OR kroger))
    """

    private var processed: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "gmail.processed") ?? []) }
        set { UserDefaults.standard.set(Array(newValue.suffix(2000)), forKey: "gmail.processed") }
    }

    enum GmailError: LocalizedError {
        case noClientID, auth(String), api(String)
        var errorDescription: String? {
            switch self {
            case .noClientID: "Add your Google client ID first (More → Gmail receipts)."
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
        Keychain.set(refresh, for: "gmail.refresh")
    }

    func signOut() { Keychain.delete("gmail.refresh") }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }

    // MARK: Import

    /// Imports any receipt emails not seen before. Returns the number of items added.
    @discardableResult
    func importNew(context: ModelContext) async throws -> Int {
        guard !isImporting, isSignedIn, !clientID.isEmpty, let refresh = Keychain.get("gmail.refresh") else { return 0 }
        isImporting = true
        defer { isImporting = false }
        let tokens = try await tokenRequest(["refresh_token": refresh, "grant_type": "refresh_token"])
        guard let access = tokens["access_token"] as? String else { throw GmailError.auth("token refresh failed") }

        let query = UserDefaults.standard.string(forKey: "gmail.query").flatMap { $0.isEmpty ? nil : $0 } ?? Self.defaultQuery
        var list = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
        list.queryItems = [.init(name: "q", value: query), .init(name: "maxResults", value: "25")]
        let listJSON = try await get(list.url!, token: access)
        let ids = ((listJSON["messages"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }
        let fresh = ids.filter { !processed.contains($0) }

        let chef = ChefAI()
        var added = 0
        for id in fresh {
            let msg = try await get(URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)?format=full")!, token: access)
            let (subject, from, date, body) = Self.extract(msg)
            let text = "From: \(from)\nSubject: \(subject)\n\n\(body)"
            let parsed = await chef.parseScan(text: String(text.prefix(6000)), labels: [])
            if !parsed.items.isEmpty {
                let store = parsed.store.isEmpty ? Self.storeName(from: from) : parsed.store
                let receipt = Receipt(store: store, date: date, total: parsed.total, rawText: text)
                context.insert(receipt)
                for p in parsed.items {
                    let loc = ShelfLife.defaultLocation(for: p.category, name: p.name)
                    let item = PantryItem(name: p.name, category: p.category, location: loc, quantity: p.quantity, unit: p.unit,
                                          purchaseDate: date, expirationDate: p.printedExpiration ?? ShelfLife.estimatedExpiration(name: p.name, category: p.category, in: loc, from: date),
                                          expirationIsEstimated: p.printedExpiration == nil, price: p.price, store: store)
                    item.receipt = receipt
                    context.insert(item)
                    added += 1
                }
                ShoppingBrain.checkOff(names: parsed.items.map(\.name), context: context)
            }
            processed.insert(id)
        }
        try? context.save()
        UserDefaults.standard.set(Date.now, forKey: "gmail.lastSync")
        return added
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
        return Data(base64Encoded: b).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func stripHTML(_ html: String) -> String {
        html.replacing(/<style[^>]*>[\s\S]*?<\/style>/.ignoresCase(), with: "")
            .replacing(/<script[^>]*>[\s\S]*?<\/script>/.ignoresCase(), with: "")
            .replacing(/<br\s*\/?>|<\/(p|div|tr|li|h\d)>/.ignoresCase(), with: "\n")
            .replacing(/<[^>]+>/, with: " ")
            .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
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
