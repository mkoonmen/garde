import SwiftUI
import SwiftData
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
            if profiles.isEmpty { context.insert(KitchenProfile()) }
            EmailReceipt.purgeJunk(context: context)
            await Notifier.requestPermission()
            if gmailAuto { _ = try? await GmailImporter.shared.importNew(context: context) }
            ShoppingBrain.refreshRunningLow(context: context)
        }
        .onChange(of: phase) { _, new in
            switch new {
            case .background:
                try? context.save()
                Notifier.reschedule(items: items, warningDays: profiles.first?.expirationWarningDays ?? 2)
                Notifier.scheduleThawReminders(plan: plan, items: items)
                WidgetCenter.shared.reloadAllTimelines()
                KitchenFeed.publish(context: context)
            case .active:
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
