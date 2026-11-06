import SwiftUI
import SwiftData
import CoreData
import WidgetKit

@main
struct GardeApp: App {
    init() { Theme.applyNavigationStyle(); NotificationRouter.shared.install() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Theme.accent)
        }
        .modelContainer(GardeStore.container)
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @Query private var profiles: [KitchenProfile]
    @Query private var items: [PantryItem]
    @Query private var plan: [MealPlanEntry]
    @AppStorage("gmail.autoImport") private var gmailAuto = false
    @AppStorage("onboarded") private var onboarded = false
    @AppStorage("whatsNew.seen") private var whatsNewSeen = ""

    @Bindable private var router = NotificationRouter.shared

    var body: some View {
        TabView(selection: $router.tab) {
            Tab("Kitchen", systemImage: "refrigerator", value: 0) { InventoryView() }
            Tab("Scan", systemImage: "barcode.viewfinder", value: 1) { ScanView() }
            Tab("Chef", systemImage: "frying.pan", value: 2) { ChefView() }
            Tab("List", systemImage: "checklist", value: 3) { ShoppingListView() }
            Tab("More", systemImage: "ellipsis.circle", value: 4) { MoreView() }
        }
        .fullScreenCover(isPresented: Binding(get: { !onboarded }, set: { if !$0 { onboarded = true } })) {
            OnboardingView { onboarded = true; whatsNewSeen = WhatsNew.version }
        }
        .sheet(isPresented: Binding(get: { onboarded && whatsNewSeen != WhatsNew.version }, set: { if !$0 { whatsNewSeen = WhatsNew.version } })) {
            NavigationStack { WhatsNewView { whatsNewSeen = WhatsNew.version } }
        }
        .task {
            KitchenProfile.merge(context: context)
            if profiles.isEmpty { context.insert(KitchenProfile()) }
            #if DEBUG
            DemoData.seedIfAsked(context: context)
            if UserDefaults.standard.object(forKey: "startTab") != nil { router.tab = UserDefaults.standard.integer(forKey: "startTab") }
            #endif
            EmailReceipt.purgeJunk(context: context)
            // First launch asks at the end of onboarding (with context), not on top of the welcome screen.
            #if DEBUG
            if onboarded && !UserDefaults.standard.bool(forKey: "demoData") { await Notifier.requestPermission() }
            #else
            if onboarded { await Notifier.requestPermission() }
            #endif
            if gmailAuto { _ = try? await GmailImporter.shared.importNew(context: context) }
            ShoppingBrain.refreshRunningLow(context: context)
        }
        #if DEBUG
        .sheet(isPresented: .constant(UserDefaults.standard.string(forKey: "screen") != nil)) {
            NavigationStack { DebugScreen(name: UserDefaults.standard.string(forKey: "screen") ?? "") }
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange).receive(on: RunLoop.main)) { _ in
            KitchenProfile.merge(context: context)   // iCloud just synced: fold any duplicate profile in
        }
        .onChange(of: phase) { _, new in
            switch new {
            case .background:
                try? context.save()
                Notifier.reschedule(items: items, warningDays: profiles.first?.expirationWarningDays ?? 2)
                Notifier.scheduleThawReminders(plan: plan, items: items)
                Notifier.scheduleWeeklyNudge(items: items)
                WidgetCenter.shared.reloadAllTimelines()
                KitchenFeed.publish(context: context)
            case .active:
                KitchenProfile.merge(context: context)
                if gmailAuto { Task { _ = try? await GmailImporter.shared.importNew(context: context) } }
                ShoppingBrain.refreshRunningLow(context: context)
            default: break
            }
        }
    }
}

extension Theme {
    /// Serif (New York) navigation titles to match the icon's script-and-serif feel.
    static func applyNavigationStyle() {
        func serif(_ style: UIFont.TextStyle, _ weight: UIFont.Weight) -> UIFont {
            let base = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: style).pointSize, weight: weight)
            let desc = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
            return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: desc, size: 0))
        }
        let nav = UINavigationBar.appearance()
        nav.largeTitleTextAttributes = [.font: serif(.largeTitle, .bold)]
        nav.titleTextAttributes = [.font: serif(.headline, .semibold)]
    }

}

#if DEBUG
/// Simulator-only: `-screen insights` opens a screen directly, for screenshots.
struct DebugScreen: View {
    let name: String
    var body: some View {
        switch name {
        case "insights": InsightsView()
        case "pricebook": PriceBookView()
        case "takeout": TakeoutView()
        case "host": HostView()
        case "timeline": DinnerTimelineView()
        case "mealprep": MealPrepView()
        case "book": RecipeBookView()
        case "journal": CookJournalView()
        case "quickadd": QuickAddView()
        case "shopping": ShoppingModeView(prices: [])
        case "allergycard": AllergyCardView()
        case "mix": MixView()
        case "settings": GardeSettingsView()
        case "onboarding": OnboardingView {}
        case "recipe":
            RecipeDetailView(title: "Lemon Chicken Piccata", summary: "Crisp thighs, bright lemon-caper pan sauce.", minutes: 35, servings: 2,
                             ingredients: ["1 1/2 lb chicken thighs", "2 tbsp capers", "1/2 cup chicken broth", "1 cup buttermilk", "2-3 cloves garlic", "Salt and pepper"],
                             steps: ["Season and sear the chicken 6 minutes per side.", "Make the pan sauce.", "Simmer 3 minutes and serve."])
        default: Text("Unknown screen \(name)")
        }
    }
}
#endif
