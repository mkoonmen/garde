import SwiftUI
import SwiftData

/// Type or dictate several groceries at once: "eggs, 2 lb chicken thighs, milk and spinach".
struct QuickAddView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var lines: [QuickAdd.Line] = []
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            List { Group {
                Section {
                    TextField("eggs, 2 lb chicken thighs, a gallon of milk and spinach", text: $text, axis: .vertical)
                        .lineLimit(3...8).focused($focused)
                        .onChange(of: text) { _, t in lines = QuickAdd.parse(t) }
                } footer: { Text("Tap the mic on the keyboard to just say what you bought. Dates are estimated from typical shelf life.") }
                if !lines.isEmpty {
                    Section("\(Plural.items(lines.count))") {
                        ForEach($lines) { $l in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(l.name).font(.body.weight(.medium))
                                    Text("\(l.quantity.formatted()) \(l.unit) · \(l.category.label) · keeps ~\(ItemEditView.keeps(l.days))").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Picker("", selection: $l.location) {
                                    ForEach([StorageLocation.fridge, .freezer, .pantry, .counter], id: \.self) { Image(systemName: $0.symbol).tag($0) }
                                }.labelsHidden().pickerStyle(.menu)
                            }
                        }
                        .onDelete { lines.remove(atOffsets: $0) }
                    }
                }
            }.listRowBackground(RowGlass()) }
            .gardePage()
            .navigationTitle("Quick add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add \(lines.count)") { save() }.disabled(lines.isEmpty) }
            }
            .onAppear { focused = true }
        }
    }

    private func save() {
        for l in lines {
            let days = ShelfLife.days(name: l.name, category: l.category, location: l.location)
            let item = PantryItem(name: l.name, category: l.category, location: l.location, quantity: l.quantity, unit: l.unit,
                                  expirationDate: Calendar.current.date(byAdding: .day, value: days, to: .now))
            if l.location == .freezer { item.frozenDate = .now }
            KitchenStock.register(item, context: context)
        }
        ShoppingBrain.checkOff(names: lines.map(\.name), context: context)
        try? context.save()
        dismiss()
    }
}
