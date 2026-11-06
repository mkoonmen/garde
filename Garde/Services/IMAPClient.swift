import Foundation
import Network

/// A small read-only IMAP client (TLS, LOGIN, SELECT, UID SEARCH, UID FETCH) for iCloud Mail and other
/// mailboxes that allow app-specific passwords. Messages are read on the phone; nothing else is contacted.
actor IMAPClient {
    enum IMAPError: LocalizedError {
        case connection(String), login, command(String)
        var errorDescription: String? {
            switch self {
            case .connection(let m): "Couldn't reach the mail server: \(m)"
            case .login: "The mail server didn't accept that email and app-specific password."
            case .command(let m): "Mail server error: \(m)"
            }
        }
    }

    private let connection: NWConnection
    private var buffer = Data()
    private var tag = 0

    init(host: String, port: UInt16 = 993) {
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tls)
    }

    // MARK: Connection

    func connect() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var resumed = false
            connection.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready: resumed = true; cont.resume()
                case .failed(let e): resumed = true; cont.resume(throwing: IMAPError.connection(e.localizedDescription))
                case .waiting(let e): resumed = true; cont.resume(throwing: IMAPError.connection(e.localizedDescription))
                case .cancelled: resumed = true; cont.resume(throwing: IMAPError.connection("cancelled"))
                default: break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
        _ = try await readLine()   // server greeting
    }

    func close() {
        connection.cancel()
    }

    private func receiveMore() async throws {
        let chunk: Data = try await withCheckedThrowingContinuation { cont in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { data, _, complete, error in
                if let error { cont.resume(throwing: IMAPError.connection(error.localizedDescription)) }
                else if let data, !data.isEmpty { cont.resume(returning: data) }
                else if complete { cont.resume(throwing: IMAPError.connection("closed")) }
                else { cont.resume(returning: Data()) }
            }
        }
        buffer.append(chunk)
    }

    private func readLine() async throws -> Data {
        while true {
            if let r = buffer.range(of: Data("\r\n".utf8)) {
                let line = buffer.subdata(in: buffer.startIndex..<r.lowerBound)
                buffer.removeSubrange(buffer.startIndex..<r.upperBound)
                return line
            }
            try await receiveMore()
        }
    }

    private func readBytes(_ n: Int) async throws -> Data {
        while buffer.count < n { try await receiveMore() }
        let out = buffer.prefix(n)
        buffer.removeFirst(n)
        return Data(out)
    }

    private func send(_ s: String) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: Data((s + "\r\n").utf8), completion: .contentProcessed { e in
                if let e { cont.resume(throwing: IMAPError.connection(e.localizedDescription)) } else { cont.resume() }
            })
        }
    }

    /// Sends a command and collects untagged lines (with any {n} literals inline) until the tagged reply.
    /// Each response is (text line, literals in order).
    private func command(_ cmd: String) async throws -> [(line: String, literals: [Data])] {
        tag += 1
        let t = "g\(tag)"
        try await send("\(t) \(cmd)")
        var out: [(String, [Data])] = []
        while true {
            var line = String(decoding: try await readLine(), as: UTF8.self)
            var lits: [Data] = []
            // A line ending in {n} is followed by n raw bytes, then the rest of the line.
            while let m = line.firstMatch(of: /\{(\d+)\}$/), let n = Int(m.1) {
                lits.append(try await readBytes(n))
                line += String(decoding: try await readLine(), as: UTF8.self)
            }
            if line.hasPrefix(t + " ") {
                let rest = line.dropFirst(t.count + 1)
                if rest.hasPrefix("OK") { return out }
                throw IMAPError.command(String(rest.prefix(160)))
            }
            out.append((line, lits))
        }
    }

    // MARK: Commands

    static func quote(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }

    func login(user: String, password: String) async throws {
        do { _ = try await command("LOGIN \(Self.quote(user)) \(Self.quote(password))") }
        catch IMAPError.command { throw IMAPError.login }
    }

    func select(_ mailbox: String = "INBOX") async throws { _ = try await command("SELECT \(Self.quote(mailbox))") }

    /// UIDs of messages received since a date, oldest first.
    func uids(since: Date) async throws -> [Int] {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "dd-MMM-yyyy"
        let lines = try await command("UID SEARCH SINCE \(f.string(from: since))")
        return lines.flatMap { l in l.line.hasPrefix("* SEARCH") ? l.line.dropFirst(8).split(separator: " ").compactMap { Int($0) } : [] }
    }

    /// From / Subject / Date headers for a batch of UIDs.
    func headers(_ uids: [Int]) async throws -> [(uid: Int, from: String, subject: String, date: Date)] {
        guard !uids.isEmpty else { return [] }
        let set = uids.map(String.init).joined(separator: ",")
        let lines = try await command("UID FETCH \(set) (UID BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE)])")
        return lines.compactMap { l in
            guard let m = l.line.firstMatch(of: /UID (\d+)/), let uid = Int(m.1), let raw = l.literals.first else { return nil }
            let h = MIMEParser.headers(String(decoding: raw, as: UTF8.self))
            return (uid, MIMEParser.decodeWords(h["from"] ?? ""), MIMEParser.decodeWords(h["subject"] ?? ""),
                    MIMEParser.date(h["date"] ?? "") ?? .now)
        }
    }

    /// The whole message (RFC 822), for reading the body.
    func message(_ uid: Int) async throws -> Data? {
        let lines = try await command("UID FETCH \(uid) (BODY.PEEK[])")
        return lines.first { !$0.literals.isEmpty }?.literals.first
    }

    func logout() async { _ = try? await command("LOGOUT"); close() }
}

/// Just enough MIME to get readable text out of a receipt email.
enum MIMEParser {
    /// Unfolded, lowercased header names → values.
    static func headers(_ block: String) -> [String: String] {
        var out: [String: String] = [:]
        var last: String?
        for raw in block.components(separatedBy: "\r\n").flatMap({ $0.components(separatedBy: "\n") }) {
            if raw.isEmpty { break }
            if raw.first == " " || raw.first == "\t", let k = last { out[k, default: ""] += " " + raw.trimmingCharacters(in: .whitespaces); continue }
            guard let c = raw.firstIndex(of: ":") else { continue }
            let k = raw[..<c].lowercased()
            out[k] = raw[raw.index(after: c)...].trimmingCharacters(in: .whitespaces)
            last = k
        }
        return out
    }

    /// "=?UTF-8?Q?Your_Walmart_order?=" → "Your Walmart order"
    static func decodeWords(_ s: String) -> String {
        var result = s
        for m in s.matches(of: /=\?([^?]+)\?([QqBb])\?([^?]*)\?=/) {
            let enc = String(m.2).uppercased(), text = String(m.3)
            let data: Data? = enc == "B" ? Data(base64Encoded: text.padding(toLength: (text.count + 3) / 4 * 4, withPad: "=", startingAt: 0))
                                         : quotedPrintable(text.replacingOccurrences(of: "_", with: " "))
            if let data { result = result.replacingOccurrences(of: String(m.0), with: string(data, charset: String(m.1))) }
        }
        return result.replacing(/\?=\s+=\?/, with: "?==?")
    }

    static func date(_ s: String) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        let clean = s.replacing(/\s*\([^)]*\)\s*$/, with: "")
        for fmt in ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm Z"] {
            f.dateFormat = fmt
            if let d = f.date(from: clean) { return d }
        }
        return nil
    }

    static func quotedPrintable(_ s: String) -> Data? {
        var out = Data(); var i = s.startIndex
        let soft = s.replacingOccurrences(of: "=\r\n", with: "").replacingOccurrences(of: "=\n", with: "")
        i = soft.startIndex
        while i < soft.endIndex {
            let c = soft[i]
            if c == "=", let end = soft.index(i, offsetBy: 3, limitedBy: soft.endIndex), let b = UInt8(soft[soft.index(after: i)..<end], radix: 16) {
                out.append(b); i = end
            } else { out.append(contentsOf: Array(String(c).utf8)); i = soft.index(after: i) }
        }
        return out
    }

    static func string(_ d: Data, charset: String?) -> String {
        let c = (charset ?? "utf-8").lowercased()
        if c.contains("8859") || c.contains("latin") || c.contains("1252") {
            return String(data: d, encoding: c.contains("1252") ? .windowsCP1252 : .isoLatin1) ?? String(decoding: d, as: UTF8.self)
        }
        return String(data: d, encoding: .utf8) ?? String(data: d, encoding: .isoLatin1) ?? String(decoding: d, as: UTF8.self)
    }

    /// Readable body text: text/plain if present, else text/html with the tags stripped.
    static func bodyText(_ raw: Data) -> String {
        var plain = "", html = ""
        func walk(_ part: String) {
            let split = part.range(of: "\r\n\r\n") ?? part.range(of: "\n\n")
            let head = split.map { String(part[..<$0.lowerBound]) } ?? part
            let body = split.map { String(part[$0.upperBound...]) } ?? ""
            let h = headers(head)
            let type = (h["content-type"] ?? "text/plain").lowercased()
            if type.hasPrefix("multipart/"), let b = param("boundary", in: h["content-type"] ?? "") {
                for sub in body.components(separatedBy: "--" + b).dropFirst() where !sub.hasPrefix("--") {
                    walk(sub.trimmingCharacters(in: CharacterSet(charactersIn: "\r\n")))
                }
                return
            }
            guard type.hasPrefix("text/plain") || type.hasPrefix("text/html") else { return }
            let enc = (h["content-transfer-encoding"] ?? "").lowercased()
            let data: Data? = enc.contains("base64") ? Data(base64Encoded: body.filter { !$0.isWhitespace }) :
                              enc.contains("quoted") ? quotedPrintable(body) : Data(body.utf8)
            let text = data.map { string($0, charset: param("charset", in: h["content-type"] ?? "")) } ?? ""
            if type.hasPrefix("text/plain") { plain += text } else { html += text }
        }
        walk(String(decoding: raw, as: UTF8.self))
        return plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? GmailImporter.stripHTML(html) : plain
    }

    static func param(_ name: String, in header: String) -> String? {
        guard let m = header.firstMatch(of: try! Regex("(?i)\(name)=\"?([^\";]+)\"?")) else { return nil }
        return m.output.count > 1 ? m.output[1].substring.map(String.init) : nil
    }
}
