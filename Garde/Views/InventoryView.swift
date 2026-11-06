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
            List { Group {
                if search.isEmpty {
                    Section { KitchenHero(items: items, filter: $filter) }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
                if !expiringSoon.isEmpty && filter == nil && search.isEmpty {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(expiringSoon.sorted { ($0.daysLeft ?? 0) < ($1.daysLeft ?? 0) }) { item in
                                    Button { editing = item } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                            Text(Theme.expiryText(item.daysLeft)).font(.caption).foregroundStyle(Theme.expiryColor(item.daysLeft))
                                            if item.canFreeze && (item.daysLeft ?? 9) >= 0 {
                                                Button { withAnimation { item.freeze() } } label: {
                                                    Label("Freeze it", systemImage: "snowflake").font(.caption2.weight(.semibold))
                                                }.buttonStyle(.bordered).controlSize(.mini).tint(.blue)
                                            }
                                        }
                                        .padding(12).frame(width: 150, alignment: .leading)
                                        .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
                                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.expiryColor(item.daysLeft).opacity(0.6), lineWidth: 1))
                                        .shadow(color: Theme.expiryColor(item.daysLeft).opacity(0.35), radius: 10, y: 4)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    } header: { Text("Use these first") }
                }

                let longFrozen = items.filter { ($0.frozenDate ?? .now) < Date.now.addingTimeInterval(-90 * 86_400) }
                    .sorted { ($0.frozenDate ?? .now) < ($1.frozenDate ?? .now) }
                if !longFrozen.isEmpty {
                    Section {
                        ForEach(longFrozen.prefix(5)) { item in
                            HStack {
                                Image(systemName: "snowflake").foregroundStyle(.cyan)
                                Text(item.name)
                                Spacer()
                                let months = Calendar.current.dateComponents([.month], from: item.frozenDate ?? .now, to: .now).month ?? 0
                                Text("\(months) mo").font(.caption.weight(.semibold)).foregroundStyle(months >= 6 ? .orange : .secondary)
                            }
                        }
                    } header: { Text("Deep in the freezer") } footer: { Text("Still safe, but best quality fades after about 3–6 months. Plan these soon.") }
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
                                Button("Ate it", systemImage: "checkmark") { item.markUsed() }.tint(.green)
                                Button("Tossed", systemImage: "trash.slash") { item.markUsed(tossed: true) }.tint(.gray)
                            }
                            .swipeActions(edge: .leading) {
                                if item.canFreeze {
                                    Button("Freeze", systemImage: "snowflake") { withAnimation { item.freeze() } }.tint(.blue)
                                } else if item.location == .freezer {
                                    Button("Thaw", systemImage: "drop") { withAnimation { item.thaw() } }.tint(.teal)
                                }
                                Button("Delete", systemImage: "trash", role: .destructive) { context.delete(item) }
                            }
                    }
                }
            }.listRowBackground(RowGlass()) }
            .gardePage()
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
                HStack(spacing: 6) {
                    Text(item.name).font(.body.weight(.medium))
                    if item.isLeftover { Text("LEFTOVER").font(.caption2.weight(.bold)).padding(.horizontal, 5).padding(.vertical, 1).background(Theme.accent.opacity(0.2), in: .capsule) }
                }
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
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form { Group {
                Section {
                    TextField("Name", text: $name)
                        .onSubmit { if item == nil && estimated { location = ShelfLife.defaultLocation(for: category, name: name); reestimate() } }
                    Picker("Category", selection: $category) { ForEach(FoodCategory.allCases) { Text($0.label).tag($0) } }
                        .onChange(of: category) { _, c in guard loaded, item == nil else { return }; location = ShelfLife.defaultLocation(for: c, name: name); reestimate() }
                    Picker("Stored in", selection: $location) { ForEach(StorageLocation.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) } }
                        .onChange(of: location) { _, _ in if loaded && estimated { reestimate() } }
                }
                Section {
                    Stepper("Quantity: \(quantity.formatted())", value: $quantity, in: 0...999, step: 0.5)
                    TextField("Unit (each, lb, oz…)", text: $unit)
                }
                Section("Expiration") {
                    Toggle("Has expiration date", isOn: $hasExpiration)
                    if hasExpiration {
                        DatePicker("Expires", selection: Binding(get: { expiration }, set: { expiration = $0; estimated = false }),
                                   displayedComponents: .date)
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
                        if let opened = item.openedDate {
                            LabeledContent("Opened", value: opened.formatted(date: .abbreviated, time: .omitted))
                        } else {
                            Button("I just opened it", systemImage: "seal") {
                                item.openedDate = .now
                                if let d = ShelfLife.openedExpiration(name: item.name, category: item.category, current: item.expirationDate) {
                                    item.expirationDate = d; expiration = d; hasExpiration = true; estimated = false
                                }
                            }
                        }
                        if let f = item.frozenDate {
                            LabeledContent("Frozen", value: f.formatted(date: .abbreviated, time: .omitted))
                            Button("Thawed it in the fridge", systemImage: "drop") { item.thaw(); dismiss() }
                        } else if item.canFreeze {
                            Button("Freeze it", systemImage: "snowflake") { item.freeze(); dismiss() }
                        }
                        Button("Used it up") { item.markUsed(); dismiss() }
                        Button("Threw it out") { item.markUsed(tossed: true); dismiss() }
                        Button("Delete", role: .destructive) { context.delete(item); dismiss() }
                    }
                }
            }.listRowBackground(RowGlass()) }
            .gardePage()
            .navigationTitle(item == nil ? "Add food" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
            .onAppear(perform: load)
        }
    }

    private func reestimate() { expiration = ShelfLife.estimatedExpiration(name: name, category: category, in: location); estimated = true }

    private func load() {
        defer { loaded = true }
        guard let item else { reestimate(); return }
        name = item.name; category = item.category; location = item.location
        quantity = item.quantity; unit = item.unit
        hasExpiration = item.expirationDate != nil; expiration = item.expirationDate ?? .now
        price = item.price.map { String(format: "%.2f", $0) } ?? ""
        store = item.store ?? ""; notes = item.notes; photo = item.photo
        estimated = item.expirationIsEstimated
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


/// Kitchen dashboard: greeting + live counts. Tapping a tile filters the list.
struct KitchenHero: View {
    let items: [PantryItem]
    @Binding var filter: StorageLocation?
    @State private var appeared = false

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }
    private var expiring: Int { items.filter { ($0.daysLeft ?? 99) <= 2 }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Text(expiring == 0 ? "Everything's fresh." : "\(expiring) thing\(expiring == 1 ? "" : "s") to use soon")
                    .font(.system(.title2, design: .serif).weight(.bold))
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 4)

            HStack(spacing: 10) {
                ForEach([StorageLocation.fridge, .freezer, .pantry], id: \.self) { loc in
                    let n = items.filter { $0.location == loc }.count
                    Button {
                        withAnimation(.spring(duration: 0.35)) { filter = filter == loc ? nil : loc }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Image(systemName: loc.symbol).font(.title3)
                                .foregroundStyle(LinearGradient(colors: [Theme.copper, Theme.cream], startPoint: .top, endPoint: .bottom))
                                .symbolEffect(.bounce, value: filter == loc)
                            Text("\(n)").font(.system(.title, design: .rounded).weight(.bold)).contentTransition(.numericText())
                            Text(loc.label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(.ultraThinMaterial, in: .rect(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(filter == loc ? Theme.copper : .white.opacity(0.12), lineWidth: filter == loc ? 1.5 : 1))
                        .shadow(color: filter == loc ? Theme.copper.opacity(0.45) : .black.opacity(0.15), radius: 14, y: 6)
                        .scaleEffect(filter == loc ? 1.03 : 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            WeekStrip()
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .onAppear { withAnimation(.spring(duration: 0.6)) { appeared = true } }
        .sensoryFeedback(.selection, trigger: filter)
    }
}

/// "This week": dinners cooked, food eaten vs. tossed, money spent on groceries.
struct WeekStrip: View {
    @Query private var logs: [CookLog]
    @Query(filter: #Predicate<PantryItem> { $0.isUsedUp }) private var finished: [PantryItem]
    @Query private var receipts: [Receipt]

    var body: some View {
        let start = Date.now.addingTimeInterval(-7 * 86_400)
        let cooked = logs.filter { $0.date >= start }.count
        let done = finished.filter { ($0.usedUpDate ?? .distantPast) >= start }
        let tossed = done.filter(\.wasTossed).count
        let spent = receipts.filter { $0.date >= start }.compactMap(\.total).reduce(0, +)
        if cooked + done.count > 0 || spent > 0 {
            HStack(spacing: 0) {
                cell("\(cooked)", "cooked", "frying.pan")
                cell("\(done.count - tossed)", "eaten", "checkmark.circle")
                cell("\(tossed)", "tossed", "trash", warn: tossed > 0)
                cell(spent.formatted(.currency(code: "USD").precision(.fractionLength(0))), "spent", "cart")
            }
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 18))
            .overlay(alignment: .topLeading) {
                Text("THIS WEEK").font(.caption2.weight(.bold)).foregroundStyle(Theme.copper).offset(x: 12, y: -14)
            }
            .padding(.top, 8)
        }
    }

    private func cell(_ v: String, _ l: String, _ icon: String, warn: Bool = false) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon).font(.caption).foregroundStyle(warn ? .orange : .secondary)
            Text(v).font(.system(.headline, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(l).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
}
