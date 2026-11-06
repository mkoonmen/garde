import SwiftUI
import SwiftData

struct KitchenHistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \KitchenEvent.date, order: .reverse) private var events: [KitchenEvent]
    let item: PantryItem
    @State private var error: String?
    private var history: [KitchenEvent] {
        Dictionary(events.filter { $0.itemID == item.id }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values.sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            Section {
                Text(item.name).font(.headline)
                Text(item.availableLabel).foregroundStyle(.secondary)
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
            ForEach(history) { event in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(event.action).font(.headline)
                        Spacer()
                        Text(event.date, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(event.explanation).font(.subheadline)
                    if event.undone { Text("Undone").font(.caption).foregroundStyle(.secondary) }
                    if KitchenStock.canUndo(event, item: item) {
                        Button("Undo this change") {
                            do { try KitchenStock.undo(event, item: item, context: context) }
                            catch { self.error = error.localizedDescription }
                        }
                    }
                }.listRowBackground(RowGlass())
            }
        }
        .gardePage().navigationTitle("Item history")
        .task {
            KitchenStock.baseline(item, context: context, existingEvents: events)
            do { try context.save() } catch { self.error = error.localizedDescription }
        }
    }
}

struct StockLevelControls: View {
    @Environment(\.modelContext) private var context
    let item: PantryItem
    @State private var problem: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.availableLabel).font(.subheadline)
            HStack {
                ForEach([1.0, 0.5, 0.1, 0], id: \.self) { fraction in
                    Button(fraction == 1 ? "Full" : fraction == 0.5 ? "Half" : fraction == 0.1 ? "Almost gone" : "Finished") {
                        item.setRemaining(fraction)
                        do { try context.save() } catch { context.rollback(); problem = error.localizedDescription }
                    }.buttonStyle(.bordered).controlSize(.small)
                }
            }
            NavigationLink("History & Undo") { KitchenHistoryView(item: item) }
            if let problem { Text(problem).font(.caption).foregroundStyle(.red) }
        }
    }
}

struct KitchenCheckView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let items: [PantryItem]
    @State private var checked: Set<UUID> = []
    @State private var problem: String?
    var body: some View {
        NavigationStack {
            List {
                if let problem { Text(problem).foregroundStyle(.red) }
                ForEach(items.filter { !checked.contains($0.id) }.prefix(3)) { item in
                    Section(item.name) {
                        Text(item.location == .freezer ? "Still in the freezer?" : "How much is left?")
                        StockLevelControls(item: item)
                        Button("Still here") {
                            item.lastCheckedDate = .now
                            checked.insert(item.id)
                        }
                        Button("Skip") { checked.insert(item.id) }
                    }
                }
            }
            .gardePage().navigationTitle("Quick kitchen check")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") {
                do { try context.save(); dismiss() } catch { problem = error.localizedDescription }
            } } }
        }
    }
}
