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

// "Hey Siri, how's my grocery budget in Garde?"
struct BudgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Grocery budget"

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = GardeStore.container.mainContext
        let start = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
        let spent = try ctx.fetch(FetchDescriptor<Receipt>()).filter { $0.date >= start }.compactMap(\.total).reduce(0, +)
        let budget = try ctx.fetch(FetchDescriptor<KitchenProfile>()).first?.monthlyBudget ?? 0
        let money = spent.formatted(.currency(code: "USD").precision(.fractionLength(0)))
        guard budget > 0 else { return .result(dialog: "You've spent \(money) on groceries this month. Set a budget in Garde's Insights.") }
        let left = (budget - spent).formatted(.currency(code: "USD").precision(.fractionLength(0)))
        return .result(dialog: spent <= budget ? "You've spent \(money) this month, \(left) left in your budget." : "You've spent \(money) this month, over your budget.")
    }
}

// "Hey Siri, what's in season in Garde?"
struct InSeasonIntent: AppIntent {
    static let title: LocalizedStringResource = "What's in season"

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "In season around here now: \(Seasonal.now().prefix(6).joined(separator: ", ")).")
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
        // "milk, eggs and bread" adds three.
        let lines = QuickAdd.parse(item)
        let names = lines.count > 1 ? lines.map(\.name) : [item.capitalized]
        for n in names { ctx.insert(ShoppingItem(name: n, category: ShoppingBrain.guessCategory(n), reason: "Added with Siri")) }
        try ctx.save()
        return .result(dialog: names.count > 1 ? "Added \(names.count) things to your list." : "Added \(item) to your list.")
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

// "Hey Siri, I used the last of the eggs in Garde"
struct UsedItemIntent: AppIntent {
    static let title: LocalizedStringResource = "I used something up"
    static let description = IntentDescription("Marks a kitchen item as used up.")
    @Parameter(title: "Item") var item: String
    @Parameter(title: "Threw it out", default: false) var tossed: Bool
    static var parameterSummary: some ParameterSummary { Summary("Used up \(\.$item)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = GardeStore.container.mainContext
        let stock = try ctx.fetch(FetchDescriptor<PantryItem>(predicate: #Predicate { !$0.isUsedUp }))
        let matches = stock.filter { ShoppingBrain.appears(item, in: $0.name) || ShoppingBrain.appears($0.name, in: item) }
            .sorted { ($0.daysLeft ?? 999) < ($1.daysLeft ?? 999) }
        guard let hit = matches.first else { return .result(dialog: "I couldn't find \(item) in your kitchen.") }
        hit.markUsed(tossed: tossed)
        ShoppingBrain.refreshRunningLow(context: ctx)
        try ctx.save()
        let left = matches.count - 1
        return .result(dialog: "Marked \(hit.name) as \(tossed ? "tossed" : "used up").\(left > 0 ? " You still have \(left) more." : "")")
    }
}

// "Hey Siri, I bought salmon in Garde"
struct BoughtItemIntent: AppIntent {
    static let title: LocalizedStringResource = "I bought something"
    static let description = IntentDescription("Adds a grocery item to your kitchen with an estimated expiration.")
    @Parameter(title: "Item") var item: String
    static var parameterSummary: some ParameterSummary { Summary("Bought \(\.$item)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = GardeStore.container.mainContext
        let name = item.prefix(1).uppercased() + item.dropFirst()
        let cat = ShoppingBrain.guessCategory(item)
        let loc = ShelfLife.defaultLocation(for: cat, name: item)
        let exp = ShelfLife.estimatedExpiration(name: item, category: cat, in: loc)
        ctx.insert(PantryItem(name: name, category: cat, location: loc, expirationDate: exp, expirationIsEstimated: true))
        ShoppingBrain.checkOff(names: [item], context: ctx)
        try ctx.save()
        return .result(dialog: "Added \(name) to your \(loc.label.lowercased()). Good until about \(exp.formatted(.dateTime.weekday(.wide).month().day())).")
    }
}

// "Hey Siri, do I have parmesan in Garde?"
struct HaveItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Do I have something"
    @Parameter(title: "Item") var item: String
    static var parameterSummary: some ParameterSummary { Summary("Do I have \(\.$item)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = GardeStore.container.mainContext
        let stock = try ctx.fetch(FetchDescriptor<PantryItem>(predicate: #Predicate { !$0.isUsedUp }))
            .filter { ShoppingBrain.appears(item, in: $0.name) || ShoppingBrain.appears($0.name, in: item) }
        guard !stock.isEmpty else { return .result(dialog: "No \(item) in your kitchen. Say \"add \(item) to my Garde list\" to put it on the list.") }
        let spoken = stock.prefix(3).map { "\($0.name) in the \($0.location.label.lowercased()), \(Theme.expiryText($0.daysLeft).lowercased())" }
        return .result(dialog: "Yes: \(spoken.joined(separator: "; ")).")
    }
}

struct GardeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: WhatsExpiringIntent(), phrases: ["What's expiring in \(.applicationName)", "What's going bad in \(.applicationName)"],
                    shortTitle: "What's expiring", systemImageName: "clock.badge.exclamationmark")
        AppShortcut(intent: TonightsDinnerIntent(), phrases: ["What's for dinner in \(.applicationName)", "Tonight's dinner in \(.applicationName)"],
                    shortTitle: "Tonight's dinner", systemImageName: "frying.pan")
        AppShortcut(intent: UsedItemIntent(), phrases: ["I used something up in \(.applicationName)", "Mark something used in \(.applicationName)"],
                    shortTitle: "Used it up", systemImageName: "checkmark.circle")
        AppShortcut(intent: BoughtItemIntent(), phrases: ["I bought something in \(.applicationName)", "Add groceries to \(.applicationName)"],
                    shortTitle: "I bought", systemImageName: "bag")
        AppShortcut(intent: HaveItemIntent(), phrases: ["Do I have something in \(.applicationName)", "Check my \(.applicationName) kitchen"],
                    shortTitle: "Do I have", systemImageName: "magnifyingglass")
        AppShortcut(intent: BudgetIntent(), phrases: ["How's my grocery budget in \(.applicationName)", "Grocery spending in \(.applicationName)"],
                    shortTitle: "Grocery budget", systemImageName: "dollarsign.circle")
        AppShortcut(intent: InSeasonIntent(), phrases: ["What's in season in \(.applicationName)"],
                    shortTitle: "In season", systemImageName: "leaf")
        AppShortcut(intent: AddToListIntent(), phrases: ["Add to my \(.applicationName) list", "Add something to \(.applicationName)"],
                    shortTitle: "Add to list", systemImageName: "cart.badge.plus")
    }
}
