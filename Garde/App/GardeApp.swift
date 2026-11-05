import SwiftUI
import SwiftData

@main
struct GardeApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Theme.accent)
        }
        .modelContainer(for: [PantryItem.self, Receipt.self, Spice.self, SavedRecipe.self, KitchenProfile.self])
    }
}

enum Theme {
    static let accent = Color(red: 0.80, green: 0.42, blue: 0.20)   // copper
    static func expiryColor(_ days: Int?) -> Color {
        guard let d = days else { return .secondary }
        if d < 0 { return .red }
        if d <= 2 { return .orange }
        if d <= 5 { return .yellow }
        return .green
    }
    static func expiryText(_ days: Int?) -> String {
        guard let d = days else { return "No date" }
        switch d {
        case ..<(-1): return "Expired \(-d)d ago"
        case -1: return "Expired yesterday"
        case 0: return "Expires today"
        case 1: return "Tomorrow"
        default: return "\(d) days"
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @Query private var profiles: [KitchenProfile]
    @Query private var items: [PantryItem]

    var body: some View {
        TabView {
            Tab("Kitchen", systemImage: "refrigerator") { InventoryView() }
            Tab("Scan", systemImage: "camera.viewfinder") { ScanView() }
            Tab("Chef", systemImage: "frying.pan") { ChefView() }
            Tab("Spices", systemImage: "leaf") { SpicesView() }
            Tab("More", systemImage: "person.crop.circle") { MoreView() }
        }
        .task {
            if profiles.isEmpty { context.insert(KitchenProfile()) }
            await Notifier.requestPermission()
        }
        .onChange(of: phase) { _, new in
            if new == .background {
                Notifier.reschedule(items: items, warningDays: profiles.first?.expirationWarningDays ?? 2)
            }
        }
    }
}
