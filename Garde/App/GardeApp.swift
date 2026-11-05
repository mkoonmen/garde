import SwiftUI
import SwiftData
import WidgetKit

@main
struct GardeApp: App {
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
    @AppStorage("gmail.autoImport") private var gmailAuto = false

    var body: some View {
        TabView {
            Tab("Kitchen", systemImage: "refrigerator") { InventoryView() }
            Tab("Scan", systemImage: "barcode.viewfinder") { ScanView() }
            Tab("Chef", systemImage: "frying.pan") { ChefView() }
            Tab("List", systemImage: "checklist") { ShoppingListView() }
            Tab("More", systemImage: "ellipsis.circle") { MoreView() }
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
                WidgetCenter.shared.reloadAllTimelines()
            case .active:
                if gmailAuto { Task { _ = try? await GmailImporter.shared.importNew(context: context) } }
                ShoppingBrain.refreshRunningLow(context: context)
            default: break
            }
        }
    }
}
