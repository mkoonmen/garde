import SwiftUI
import SwiftData
import WidgetKit

@main
struct GardeApp: App {
    init() { Theme.applyNavigationStyle() }

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

    var body: some View {
        TabView {
            Tab("Kitchen", systemImage: "refrigerator") { InventoryView() }
            Tab("Scan", systemImage: "barcode.viewfinder") { ScanView() }
            Tab("Chef", systemImage: "frying.pan") { ChefView() }
            Tab("List", systemImage: "checklist") { ShoppingListView() }
            Tab("More", systemImage: "ellipsis.circle") { MoreView() }
        }
        .toolbarBackground(Theme.page, for: .tabBar)
        .fullScreenCover(isPresented: Binding(get: { !onboarded }, set: { if !$0 { onboarded = true } })) {
            OnboardingView { onboarded = true }
        }
        .task {
            if profiles.isEmpty { context.insert(KitchenProfile()) }
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
