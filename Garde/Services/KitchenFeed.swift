import Foundation
import SwiftData

/// Publishes a small read-only kitchen snapshot for Koonmen OS (the TVs).
/// Garde writes it to its iCloud Drive folder; it appears on the Mac at
///   ~/Library/Mobile Documents/iCloud~com~michaelkoonmen~garde/Documents/garde-kitchen.json
/// and the Horizon Home bridge can serve it to the TVs. No network server on the phone, no tokens.
/// Format is documented in docs/KOONMEN_OS.md.
@MainActor
enum KitchenFeed {
    struct Snapshot: Codable {
        struct Item: Codable { var name: String; var where_: String; var daysLeft: Int?
            enum CodingKeys: String, CodingKey { case name, where_ = "where", daysLeft = "days_left" } }
        struct Dinner: Codable { var title: String; var summary: String; var minutes: Int; var ingredients: [String]; var steps: [String] }
        struct CookNow: Codable { var title: String; var step: Int; var total: Int; var text: String; var timerEndsAt: Date? }
        var format = "garde-kitchen/v1"
        var updatedAt = Date()
        var tonight: Dinner?
        var useFirst: [Item]
        var shoppingCount: Int
        var cooking: CookNow?
    }

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "feed.enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "feed.enabled") }
    }

    private static var cooking: Snapshot.CookNow?

    static var folder: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: GardeStore.cloudContainer)?.appendingPathComponent("Documents", isDirectory: true)
    }
    static var isAvailable: Bool { folder != nil }

    /// Called from cook mode on every step change so the kitchen TV can follow along.
    static func setCooking(title: String?, step: Int = 0, total: Int = 0, text: String = "", timerEndsAt: Date? = nil, context: ModelContext) {
        cooking = title.map { Snapshot.CookNow(title: $0, step: step + 1, total: total, text: text, timerEndsAt: timerEndsAt) }
        publish(context: context)
    }

    static func publish(context: ModelContext) {
        guard enabled else { return }
        let items = (try? context.fetch(FetchDescriptor<PantryItem>(predicate: #Predicate { !$0.isUsedUp }))) ?? []
        let today = Calendar.current.startOfDay(for: .now)
        let plan = (try? context.fetch(FetchDescriptor<MealPlanEntry>(predicate: #Predicate { $0.day == today })))?.first
        let list = (try? context.fetch(FetchDescriptor<ShoppingItem>(predicate: #Predicate { !$0.isChecked })))?.count ?? 0
        let snap = Snapshot(
            tonight: plan.map { .init(title: $0.title, summary: $0.summary, minutes: $0.minutes, ingredients: $0.ingredients, steps: $0.steps) },
            useFirst: items.filter { ($0.daysLeft ?? 99) <= 3 }.sorted { ($0.daysLeft ?? 0) < ($1.daysLeft ?? 0) }.prefix(6)
                .map { .init(name: $0.name, where_: $0.location.rawValue, daysLeft: $0.daysLeft) },
            shoppingCount: list, cooking: cooking)
        Task.detached(priority: .utility) {
            guard let folder = FileManager.default.url(forUbiquityContainerIdentifier: GardeStore.cloudContainer)?
                .appendingPathComponent("Documents", isDirectory: true) else { return }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]; enc.dateEncodingStrategy = .iso8601
            try? enc.encode(snap).write(to: folder.appendingPathComponent("garde-kitchen.json"), options: .atomic)
        }
    }
}
