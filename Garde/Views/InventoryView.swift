import SwiftUI
import SwiftData

struct InventoryView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<PantryItem> { !$0.isUsedUp }, sort: \PantryItem.name) private var items: [PantryItem]
    @State private var filter: StorageLocation?
    @State private var search = ""
    @State private var editing: PantryItem?
    @State private var adding = false

    private var visible: [PantryItem] {
        items.filter { (filter == nil || $0.location == filter) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
            .sorted { ($0.daysLeft ?? 9999) < ($1.daysLeft ?? 9999) }
    }
    private var expiringSoon: [PantryItem] { items.filter { ($0.daysLeft ?? 99) <= 2 } }

    var body: some View {
        NavigationStack {
            List {
                if !expiringSoon.isEmpty && filter == nil && search.isEmpty {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(expiringSoon.sorted { ($0.daysLeft ?? 0) < ($1.daysLeft ?? 0) }) { item in
                                    Button { editing = item } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                            Text(Theme.expiryText(item.daysLeft)).font(.caption).foregroundStyle(Theme.expiryColor(item.daysLeft))
                                        }
                                        .padding(10).frame(width: 140, alignment: .leading)
                                        .background(.thinMaterial, in: .rect(cornerRadius: 12))
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    } header: { Text("Use these first") }
                }

                Section {
                    Picker("Where", selection: $filter) {
                        Text("All").tag(StorageLocation?.none)
                        ForEach(StorageLocation.allCases) { Text($0.label).tag(StorageLocation?.some($0)) }
                    }.pickerStyle(.segmented)
                }

                Section("\(visible.count) items") {
                    if visible.isEmpty {
                        ContentUnavailableView("Nothing here yet", systemImage: "cart",
                                               description: Text("Scan a receipt or snap your groceries in the Scan tab, or tap + to add by hand."))
                    }
                    ForEach(visible) { item in
                        Button { editing = item } label: { ItemRow(item: item) }.buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button("Used up", systemImage: "checkmark") { item.isUsedUp = true }.tint(.green)
                                Button("Delete", systemImage: "trash", role: .destructive) { context.delete(item) }
                            }
                    }
                }
            }
            .navigationTitle("Kitchen")
            .searchable(text: $search, prompt: "Search food")
            .toolbar { Button("Add", systemImage: "plus") { adding = true } }
            .sheet(item: $editing) { ItemEditView(item: $0) }
            .sheet(isPresented: $adding) { ItemEditView(item: nil) }
        }
    }
}

struct ItemRow: View {
    let item: PantryItem
    var body: some View {
        HStack(spacing: 12) {
            if let data = item.photo, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill().frame(width: 44, height: 44).clipShape(.rect(cornerRadius: 8))
            } else {
                Image(systemName: item.location.symbol).frame(width: 44, height: 44)
                    .background(.quaternary, in: .rect(cornerRadius: 8)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.body.weight(.medium))
                Text("\(item.quantity.formatted()) \(item.unit) · \(item.category.label)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Theme.expiryText(item.daysLeft)).font(.caption.weight(.semibold)).foregroundStyle(Theme.expiryColor(item.daysLeft))
                if item.expirationIsEstimated && item.expirationDate != nil { Text("est.").font(.caption2).foregroundStyle(.tertiary) }
            }
        }
        .contentShape(.rect)
    }
}

struct ItemEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let item: PantryItem?

    @State private var name = ""
    @State private var category: FoodCategory = .other
    @State private var location: StorageLocation = .fridge
    @State private var quantity = 1.0
    @State private var unit = "each"
    @State private var hasExpiration = true
    @State private var expiration = Date()
    @State private var estimated = true
    @State private var price = ""
    @State private var store = ""
    @State private var notes = ""
    @State private var photo: Data?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Picker("Category", selection: $category) { ForEach(FoodCategory.allCases) { Text($0.label).tag($0) } }
                        .onChange(of: category) { _, c in if item == nil { location = ShelfLife.defaultLocation(for: c); reestimate() } }
                    Picker("Stored in", selection: $location) { ForEach(StorageLocation.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) } }
                        .onChange(of: location) { _, _ in if estimated { reestimate() } }
                }
                Section {
                    Stepper("Quantity: \(quantity.formatted())", value: $quantity, in: 0...999, step: 0.5)
                    TextField("Unit (each, lb, oz…)", text: $unit)
                }
                Section("Expiration") {
                    Toggle("Has expiration date", isOn: $hasExpiration)
                    if hasExpiration {
                        DatePicker("Expires", selection: $expiration, displayedComponents: .date)
                            .onChange(of: expiration) { _, _ in estimated = false }
                        if estimated { Text("Estimated from typical shelf life. Change it if the package says otherwise.").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                Section("Purchase") {
                    TextField("Price", text: $price).keyboardType(.decimalPad)
                    TextField("Store", text: $store)
                }
                Section("Notes") { TextField("Notes", text: $notes, axis: .vertical) }
                Section { PhotoField(data: $photo) }
                if let item {
                    Section {
                        Button("Mark used up") { item.isUsedUp = true; dismiss() }
                        Button("Delete", role: .destructive) { context.delete(item); dismiss() }
                    }
                }
            }
            .navigationTitle(item == nil ? "Add food" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
            .onAppear(perform: load)
        }
    }

    private func reestimate() { expiration = ShelfLife.estimatedExpiration(for: category, in: location); estimated = true }

    private func load() {
        guard let item else { reestimate(); return }
        name = item.name; category = item.category; location = item.location
        quantity = item.quantity; unit = item.unit
        hasExpiration = item.expirationDate != nil; expiration = item.expirationDate ?? .now
        price = item.price.map { String(format: "%.2f", $0) } ?? ""
        store = item.store ?? ""; notes = item.notes; photo = item.photo
        // set last so the onChange handlers above don't overwrite it
        DispatchQueue.main.async { estimated = item.expirationIsEstimated }
    }

    private func save() {
        let target = item ?? { let n = PantryItem(name: name); context.insert(n); return n }()
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.category = category; target.location = location
        target.quantity = quantity; target.unit = unit
        target.expirationDate = hasExpiration ? expiration : nil
        target.expirationIsEstimated = estimated
        target.price = Double(price); target.store = store.isEmpty ? nil : store
        target.notes = notes; target.photo = photo
        dismiss()
    }
}
