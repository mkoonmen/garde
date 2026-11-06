import SwiftUI
import SwiftData

/// Start any part of Garde over, one category at a time, or everything at once.
/// Every reset asks first and can't be undone (export a backup first if you might want it back).
struct ResetView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("onboarded") private var onboarded = true
    @State private var pending: Category?
    @State private var done: String?

    enum Category: String, CaseIterable, Identifiable {
        case kitchen = "Kitchen inventory"
        case history = "Used-up & tossed history"
        case receipts = "Receipts & spending"
        case spices = "Spice rack"
        case list = "Shopping list"
        case plan = "Week plan"
        case recipes = "Saved recipes"
        case taste = "Taste memory (ratings)"
        case bar = "Bar & cellar"
        case profile = "Allergies & tastes"
        case shared = "Shared recipes inbox"
        case deals = "Deals & store settings"
        case gmail = "Gmail connection"
        case everything = "Everything"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .kitchen: "refrigerator"; case .history: "clock.arrow.circlepath"; case .receipts: "receipt"
            case .spices: "leaf"; case .list: "checklist"; case .plan: "calendar"; case .recipes: "bookmark"
            case .taste: "star"; case .bar: "wineglass"; case .profile: "heart.text.square"; case .shared: "square.and.arrow.down"
            case .deals: "tag"; case .gmail: "envelope"; case .everything: "arrow.counterclockwise.circle"
            }
        }
        var warning: String {
            switch self {
            case .everything: "Erases all of Garde's data on this iPhone (and in iCloud if sync is on) and starts setup again."
            case .profile: "Clears your allergies, likes, dislikes and diet notes. The chef will no longer avoid your allergens until you add them again."
            case .gmail: "Disconnects Gmail and forgets which receipts were already imported."
            default: "Deletes all \(rawValue.lowercased()). This can't be undone."
            }
        }
    }

    var body: some View {
        List { Group {
            Section {
                ForEach(Category.allCases.filter { $0 != .everything }) { c in
                    Button(role: .destructive) { pending = c } label: { Label(c.rawValue, systemImage: c.icon) }
                }
            } footer: { Text("Each one starts that part over. Tip: More → Export all data first if you might want it back.") }
            Section {
                Button(role: .destructive) { pending = .everything } label: {
                    Label("Reset everything", systemImage: Category.everything.icon).font(.headline)
                }
            }
            if let done { Section { Label(done, systemImage: "checkmark.circle.fill").foregroundStyle(.green) } }
        }.listRowBackground(RowGlass()) }
        .gardePage()
        .navigationTitle("Reset")
        .confirmationDialog(pending.map { "Reset \($0.rawValue.lowercased())?" } ?? "", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible, presenting: pending) { c in
            Button("Reset \(c.rawValue)", role: .destructive) { reset(c) }
        } message: { c in Text(c.warning) }
    }

    private func wipe<T: PersistentModel>(_ type: T.Type, where predicate: Predicate<T>? = nil) {
        let items = (try? context.fetch(FetchDescriptor<T>(predicate: predicate))) ?? []
        items.forEach(context.delete)
    }

    private func reset(_ c: Category) {
        switch c {
        case .kitchen: wipe(PantryItem.self, where: #Predicate { !$0.isUsedUp })
        case .history: wipe(PantryItem.self, where: #Predicate { $0.isUsedUp })
        case .receipts: wipe(Receipt.self)
        case .spices: wipe(Spice.self)
        case .list: wipe(ShoppingItem.self)
        case .plan: wipe(MealPlanEntry.self)
        case .recipes: wipe(SavedRecipe.self)
        case .taste: wipe(CookLog.self)
        case .bar: wipe(BarBottle.self)
        case .profile:
            wipe(KitchenProfile.self)
            context.insert(KitchenProfile())
        case .shared: RecipeInbox.load().forEach { RecipeInbox.remove($0.id) }
        case .deals:
            ["deals.zip", "deals.stores", "deals.enabled", "deals.last"].forEach { UserDefaults.standard.removeObject(forKey: $0) }
            DealsService.shared.deals = []
        case .gmail:
            GmailImporter.shared.signOut()
            ["gmail.processed", "gmail.lastSync", "gmail.autoImport", "gmail.query"].forEach { UserDefaults.standard.removeObject(forKey: $0) }
        case .everything:
            for cat in Category.allCases where cat != .everything && cat != .profile { reset(cat) }
            wipe(KitchenProfile.self)
            ["fridgeCheck.last"].forEach { UserDefaults.standard.removeObject(forKey: $0) }
            try? context.save()
            onboarded = false   // shows first-run setup again
            return
        }
        try? context.save()
        withAnimation { done = "\(c.rawValue) reset." }
        pending = nil
    }
}
