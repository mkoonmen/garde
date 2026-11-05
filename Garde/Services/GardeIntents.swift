import AppIntents
import SwiftData

// "Hey Siri, what's expiring in Garde?"
struct WhatsExpiringIntent: AppIntent {
    static let title: LocalizedStringResource = "What's expiring"
    static let description = IntentDescription("Lists food that expires in the next few days.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = GardeStore.container.mainContext
        let items = try ctx.fetch(FetchDescriptor<PantryItem>(predicate: #Predicate { !$0.isUsedUp }))
            .filter { ($0.daysLeft ?? 99) <= 3 }
            .sorted { ($0.daysLeft ?? 0) < ($1.daysLeft ?? 0) }
        guard !items.isEmpty else { return .result(dialog: "Nothing's expiring in the next three days.") }
        let spoken = items.prefix(6).map { "\($0.name), \(Theme.expiryText($0.daysLeft).lowercased())" }.joined(separator: "; ")
        return .result(dialog: "\(spoken).")
    }
}

// "Hey Siri, add eggs to my Garde list"
struct AddToListIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to shopping list"
    @Parameter(title: "Item") var item: String

    static var parameterSummary: some ParameterSummary { Summary("Add \(\.$item) to the Garde list") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = GardeStore.container.mainContext
        ctx.insert(ShoppingItem(name: item.capitalized, category: ShoppingBrain.guessCategory(item), reason: "Added with Siri"))
        try ctx.save()
        return .result(dialog: "Added \(item) to your list.")
    }
}

// "Hey Siri, what's for dinner in Garde?"
struct TonightsDinnerIntent: AppIntent {
    static let title: LocalizedStringResource = "What's for dinner"

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = GardeStore.container.mainContext
        let today = Calendar.current.startOfDay(for: .now)
        let plan = try ctx.fetch(FetchDescriptor<MealPlanEntry>(predicate: #Predicate { $0.day == today })).first
        if let plan { return .result(dialog: "Tonight is \(plan.title). \(plan.summary)") }
        let expiring = try ctx.fetch(FetchDescriptor<PantryItem>(predicate: #Predicate { !$0.isUsedUp }))
            .filter { ($0.daysLeft ?? 99) <= 2 }.prefix(3).map(\.name)
        return .result(dialog: expiring.isEmpty
            ? "Nothing's planned tonight. Open Garde's Chef tab for ideas."
            : "Nothing's planned, but use up \(expiring.joined(separator: ", ")). Open Garde for ideas.")
    }
}

struct GardeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: WhatsExpiringIntent(), phrases: ["What's expiring in \(.applicationName)", "What's going bad in \(.applicationName)"],
                    shortTitle: "What's expiring", systemImageName: "clock.badge.exclamationmark")
        AppShortcut(intent: TonightsDinnerIntent(), phrases: ["What's for dinner in \(.applicationName)", "Tonight's dinner in \(.applicationName)"],
                    shortTitle: "Tonight's dinner", systemImageName: "frying.pan")
        AppShortcut(intent: AddToListIntent(), phrases: ["Add to my \(.applicationName) list", "Add something to \(.applicationName)"],
                    shortTitle: "Add to list", systemImageName: "cart.badge.plus")
    }
}
