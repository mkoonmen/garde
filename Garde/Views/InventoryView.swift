import SwiftUI
import SwiftData

struct InventoryView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<PantryItem> { !$0.isUsedUp }, sort: \PantryItem.name) private var items: [PantryItem]
    @State private var filter: StorageLocation?
    @State private var kind: FoodCategory?
    @State private var search = ""
    @State private var editing: PantryItem?
    @State private var adjusting: PantryItem?
    @State private var adding = false
    @State private var quickAdding = false
    @State private var checkingKitchen = false
    @AppStorage("kitchen.check.snoozed") private var checkSnoozed = 0.0
    @State private var pendingExpired: (items: [PantryItem], tossed: Bool)?
    @Query private var spices: [Spice]
    @Query private var profiles: [KitchenProfile]
    @Query private var logs: [CookLog]

    private var availableCategories: [FoodCategory] {
        ShoppingBrain.aisleOrder.filter { k in items.contains { $0.category == k && (filter == nil || $0.location == filter) } }
    }

    private var visible: [PantryItem] {
        items.filter { (filter == nil || $0.location == filter) && (kind == nil || $0.category == kind) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
            .sorted { ($0.daysLeft ?? 9999) < ($1.daysLeft ?? 9999) }
    }
    private var uncheckedItems: [PantryItem] {
        items.filter { ($0.lastCheckedDate ?? $0.purchaseDate) < Date.now.addingTimeInterval(-7 * 86_400) }
            .sorted { ($0.lastCheckedDate ?? $0.purchaseDate) < ($1.lastCheckedDate ?? $1.purchaseDate) }
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
                if GardeStore.storeIsTemporary {
                    Section { Label("Garde couldn't open your saved kitchen this time, so nothing you add will be kept. Close Garde fully and reopen it.", systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.red) }
                }
                if search.isEmpty && filter == nil && kind == nil {
                    TonightChoicesView(items: items, spices: spices, profile: profiles.first, logs: logs)
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
                    } header: {
                        HStack {
                            Text("Use these first")
                            Spacer()
                            Button("Cook with these", systemImage: "frying.pan") {
                                let names = expiringSoon.sorted { ($0.daysLeft ?? 0) < ($1.daysLeft ?? 0) }.prefix(4).map(\.name)
                                NotificationRouter.shared.mood = "Use up " + ListFormatter.localizedString(byJoining: names) + " before they go bad"
                                NotificationRouter.shared.tab = 2
                            }.font(.caption.weight(.semibold)).textCase(nil)
                        }
                    }
                }

                let expired = items.filter { ($0.daysLeft ?? 0) < -2 && $0.location != .freezer }
                if !expired.isEmpty && filter == nil && search.isEmpty {
                    Section {
                        Text(expired.prefix(6).map(\.name).joined(separator: ", ") + (expired.count > 6 ? "…" : ""))
                            .font(.subheadline).foregroundStyle(.secondary)
                        HStack {
                            Button("Toss all \(expired.count)", systemImage: "trash") { pendingExpired = (expired, true) }.tint(.red)
                            Spacer()
                            Button("We ate them", systemImage: "checkmark") { pendingExpired = (expired, false) }
                        }.buttonStyle(.bordered)
                    } header: { Text("Past their date") } footer: { Text("Clear them out so expirations and the chef stay accurate. Tossed items count toward waste.") }
                }
                let longFrozen = items.filter { $0.location == .freezer && ($0.frozenDate ?? .now) < Date.now.addingTimeInterval(-90 * 86_400) }
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
                    let kinds = availableCategories
                    if kinds.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                chip("All", nil, symbol: "square.grid.2x2")
                                ForEach(kinds) { k in chip(k.label, k, symbol: k.symbol) }
                            }.padding(.vertical, 2)
                        }
                    }
                }

                if search.isEmpty && filter == nil && checkSnoozed < Date.now.timeIntervalSince1970 && !uncheckedItems.isEmpty {
                    Section {
                        Button("Check a few items", systemImage: "checkmark.circle") { checkingKitchen = true }
                        Button("Later") { checkSnoozed = Date.now.addingTimeInterval(3 * 86_400).timeIntervalSince1970 }
                    } header: { Text("Keep your Kitchen current") }
                }
                Section("\(Plural.items(visible.count))") {
                    if visible.isEmpty {
                        ContentUnavailableView("Nothing here yet", systemImage: "cart",
                                               description: Text("Scan a receipt or snap your groceries in the Scan tab, or tap + to add by hand."))
                    }
                    ForEach(visible) { item in
                        Button { editing = item } label: { ItemRow(item: item) }.buttonStyle(.plain)
                            .contextMenu {
                                Button("Amount & history", systemImage: "scalemass") { adjusting = item }
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Ate it", systemImage: "checkmark") { item.markUsed() }.tint(.green)
                                Button("Tossed", systemImage: "trash.slash") { item.markUsed(tossed: true) }.tint(.gray)
                            }
                            .swipeActions(edge: .leading) {
                                if !item.isOpened && !item.isLeftover {
                                    Button("Opened", systemImage: "seal") { withAnimation { item.open() } }.tint(Theme.copper)
                                }
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
            .onChange(of: availableCategories) { _, categories in
                if let kind, !categories.contains(kind) || categories.count < 2 { self.kind = nil }
            }
            .searchable(text: $search, prompt: "Search food")
            .confirmationDialog(pendingExpired.map { $0.tossed ? "Toss \(Plural.items($0.items.count))?" : "Mark \(Plural.items($0.items.count)) eaten?" } ?? "",
                                isPresented: Binding(get: { pendingExpired != nil }, set: { if !$0 { pendingExpired = nil } }), titleVisibility: .visible) {
                Button(pendingExpired?.tossed == true ? "Toss them" : "We ate them", role: pendingExpired?.tossed == true ? .destructive : nil) {
                    if let p = pendingExpired { withAnimation { p.items.forEach { $0.markUsed(tossed: p.tossed) } }; try? context.save() }
                    pendingExpired = nil
                }
            } message: { Text("You can bring any back from More → Used-up history.") }

            .toolbar {
                Menu {
                    Button("Add one item", systemImage: "plus") { adding = true }
                    Button("Quick add several (type or talk)", systemImage: "text.badge.plus") { quickAdding = true }
                } label: { Label("Add", systemImage: "plus") } primaryAction: { adding = true }
            }
            .sheet(isPresented: $checkingKitchen) { KitchenCheckView(items: uncheckedItems) }
            .sheet(isPresented: $quickAdding) { QuickAddView() }
            .sheet(item: $adjusting) { item in
                NavigationStack {
                    List { StockLevelControls(item: item) }.gardePage().navigationTitle(item.name)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { adjusting = nil } } }
                }
            }
            .sheet(item: $editing) { ItemEditView(item: $0) }
            .sheet(isPresented: $adding) { ItemEditView(item: nil) }
        }
    }

    private func chip(_ title: String, _ k: FoodCategory?, symbol: String) -> some View {
        let on = kind == k
        let n = k.map { c in items.filter { $0.category == c && (filter == nil || $0.location == filter) }.count }
        return Button { withAnimation(.snappy) { kind = k } } label: {
            Label(n.map { "\(title) \($0)" } ?? title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(on ? Theme.copper.opacity(0.35) : Color.white.opacity(0.08), in: .capsule)
                .overlay(Capsule().strokeBorder(on ? Theme.copper : .clear, lineWidth: 1))
        }.buttonStyle(.plain)
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
                    if item.isOpened && !item.isLeftover { Text("OPENED").font(.caption2.weight(.bold)).padding(.horizontal, 5).padding(.vertical, 1).background(Theme.copper.opacity(0.25), in: .capsule) }
                    if item.isLeftover { Text("LEFTOVER").font(.caption2.weight(.bold)).padding(.horizontal, 5).padding(.vertical, 1).background(Theme.accent.opacity(0.2), in: .capsule) }
                }
                Text(item.availableLabel + " · " + item.category.label).font(.caption).foregroundStyle(.secondary)
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
    /// "5 days", "3 mo", "1 yr"
    static func keeps(_ d: Int) -> String {
        d >= 365 ? "\(d / 365) yr" : d >= 60 ? "\(d / 30) mo" : "\(d) day\(d == 1 ? "" : "s")"
    }
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let item: PantryItem?

    @State private var name = ""
    @State private var category: FoodCategory = .other
    @State private var storage = PantryStorage(expirationDate: .now)
    @State private var quantity = 1.0
    @State private var unit = "each"
    @State private var price = ""
    @State private var store = ""
    @State private var notes = ""
    @State private var photo: Data?
    @State private var loaded = false
    @State private var ingredientOverride = ""
    @State private var packageAmount = 0.0
    @State private var packageUnit = "ml"
    @State private var saveProblem: String?

    var body: some View {
        NavigationStack {
            Form { Group {
                if let saveProblem { Section { Text(saveProblem).foregroundStyle(.red) } }
                if let item { Section { NavigationLink("Item history & Undo") { KitchenHistoryView(item: item) } } }
                Section("Recipe matching & package size") {
                    TextField("Recipe ingredient (optional)", text: $ingredientOverride)
                    Text("Use a simple ingredient name, such as milk or almond milk. The product name above keeps its brand.").font(.caption).foregroundStyle(.secondary)
                    TextField("Amount per package", value: $packageAmount, format: .number).keyboardType(.decimalPad)
                    Picker("Package unit", selection: $packageUnit) {
                        ForEach(["ml", "l", "fl oz", "pint", "cup", "g", "kg", "oz", "lb", "each"], id: \.self) { Text($0).tag($0) }
                    }
                    Text("Leave package amount at zero to use the label or recorded quantity.").font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    TextField("Name", text: $name)
                        .onSubmit { if item == nil && storage.expirationIsEstimated { chooseDefaultLocation() } }
                    Picker("Category", selection: $category) { ForEach(FoodCategory.allCases) { Text($0.label).tag($0) } }
                        .onChange(of: category) { _, _ in if loaded && item == nil { chooseDefaultLocation() } }
                    Picker("Stored in", selection: Binding(get: { storage.location }, set: { location in
                        storage.location = location
                        if storage.expirationIsEstimated && storage.expirationDate != nil { reestimate() }
                    })) { ForEach(StorageLocation.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) } }
                    Toggle(isOn: Binding(get: { storage.openedDate != nil }, set: { opened in
                        if opened { storage.open(name: name, category: category, on: .now) }
                        else { storage.unopen() }
                    })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Opened")
                            Text(openedHint).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Stepper("Quantity: \(quantity.formatted())", value: $quantity, in: 0...999, step: 0.5)
                    TextField("Unit (each, lb, oz…)", text: $unit)
                }
                Section("Expiration") {
                    Toggle("Has expiration date", isOn: Binding(get: { storage.expirationDate != nil }, set: { enabled in
                        if enabled { reestimate() } else { storage.expirationDate = nil }
                    }))
                    if storage.expirationDate != nil {
                        DatePicker("Expires", selection: Binding(get: { storage.expirationDate ?? .now }, set: { storage.expirationDate = $0; storage.expirationIsEstimated = false }),
                                   displayedComponents: .date)
                        if storage.expirationIsEstimated { Text("Estimated from typical shelf life. Change it if the package says otherwise.").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if let item, !item.isUsedUp {
                    Section {
                        Button("Cook something with \(item.name)", systemImage: "frying.pan") {
                            save()   // keep any edits, then go cook (save() closes the sheet)
                            NotificationRouter.shared.mustUse = item.name
                            NotificationRouter.shared.tab = 2
                        }
                    }
                }
                if !name.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section("How long it keeps") {
                        HStack {
                            ForEach([StorageLocation.fridge, .freezer, .pantry], id: \.self) { loc in
                                let d = ShelfLife.days(name: name, category: category, location: loc)
                                VStack(spacing: 2) {
                                    Image(systemName: loc.symbol).foregroundStyle(loc == storage.location ? Theme.copper : .secondary)
                                    Text(Self.keeps(d)).font(.subheadline.weight(.semibold)).monospacedDigit()
                                    Text(loc.label).font(.caption2).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity)
                            }
                        }
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
                        if let o = storage.openedDate {
                            LabeledContent("Opened", value: o.formatted(date: .abbreviated, time: .omitted))
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

    private func chooseDefaultLocation() {
        guard storage.openedDate == nil else { return }
        storage.location = ShelfLife.defaultLocation(for: category, name: name)
        if storage.expirationIsEstimated && storage.expirationDate != nil { reestimate() }
    }

    private func reestimate() {
        let sealed = ShelfLife.estimatedExpiration(name: name, category: category, in: storage.location, from: item?.purchaseDate ?? .now)
        if let opened = storage.openedDate {
            storage.expirationDate = ShelfLife.openedExpiration(name: name, category: category, current: storage.unopenedExpiration ?? sealed, openedOn: opened)
        } else {
            storage.expirationDate = sealed
        }
        storage.expirationIsEstimated = true
    }

    private func load() {
        guard !loaded else { return }
        defer { loaded = true }
        guard let item else { reestimate(); return }
        name = item.name; category = item.category; storage = item.storage
        ingredientOverride = item.ingredientOverride; packageAmount = item.packageAmount; packageUnit = item.packageUnit
        quantity = item.quantity; unit = item.unit
        price = item.price.map { String(format: "%.2f", $0) } ?? ""
        store = item.store ?? ""; notes = item.notes; photo = item.photo
    }

    private var openedHint: String {
        let n = name.isEmpty ? "it" : name.lowercased()
        let fridge = ShelfLife.needsFridgeAfterOpening(name: name, category: category)
        guard let days = ShelfLife.rule(for: name, category: category)?.opened ?? (category == .condiments ? 60 : category == .canned ? 4 : nil) else {
            return storage.openedDate != nil ? "Opened" : "Still sealed"
        }
        let keep = ItemEditView.keeps(days)
        return storage.openedDate != nil ? "Good about \(keep) after opening\(fridge ? ", in the fridge" : "")"
                      : "Once opened, \(n) keeps about \(keep)\(fridge ? " in the fridge" : "")"
    }

    private func save() {
        let target = item ?? { let n = PantryItem(name: name); context.insert(n); return n }()
        let before = PantrySnapshot(target)
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.category = category; target.storage = storage
        if storage.location != .freezer { target.frozenDate = nil } else if target.frozenDate == nil { target.frozenDate = .now }
        if target.quantity != quantity || target.unit != unit { target.remainingAmount = nil }
        target.quantity = quantity; target.unit = unit
        target.price = Double(price); target.store = store.isEmpty ? nil : store
        target.notes = notes; target.photo = photo
        target.ingredientOverride = ingredientOverride.trimmingCharacters(in: .whitespaces)
        if target.packageAmount != packageAmount || target.packageUnit != packageUnit { target.remainingAmount = nil }
        target.packageAmount = max(0, packageAmount); target.packageUnit = packageUnit
        if item == nil { KitchenStock.baseline(target, context: context) }
        else if before != PantrySnapshot(target) {
            context.insert(KitchenEvent(itemID: target.id, action: "Edited", explanation: "You updated this item.", before: before, after: PantrySnapshot(target)))
        }
        do { try context.save(); dismiss() }
        catch { context.rollback(); saveProblem = error.localizedDescription }
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
            VStack(alignment: .leading, spacing: 6) {
                Text(greeting).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.bottom, 2)
                Text(expiring == 0 ? "Everything's fresh." : "\(expiring) thing\(expiring == 1 ? "" : "s") to use soon")
                    .font(.system(.title2, design: .serif).weight(.bold))
                    .contentTransition(.numericText())
                let value = items.compactMap(\.price).reduce(0, +)
                let atRisk = items.filter { ($0.daysLeft ?? 99) <= 2 }.compactMap(\.price).reduce(0, +)
                if value >= 5 {
                    Text("\(value.formatted(.currency(code: "USD").precision(.fractionLength(0)))) of food on hand\(atRisk >= 1 ? " · \(atRisk.formatted(.currency(code: "USD").precision(.fractionLength(0)))) at risk" : "")")
                        .font(.caption).foregroundStyle(atRisk >= 1 ? Color.orange : Color.secondary)
                }
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
            .overlay(alignment: .topTrailing) {
                if let streak = Self.noWasteStreak(finished), streak >= 3 {
                    Label("\(streak) days, nothing wasted", systemImage: "leaf.fill")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.green)
                        .padding(.horizontal, 8).padding(.vertical, 3).background(.green.opacity(0.15), in: .capsule)
                        .offset(x: -8, y: -16)
                }
            }
            .padding(.top, 8)
        }
    }

    /// Days since you last threw food away (nil if you never have, or nothing has been used yet).
    static func noWasteStreak(_ finished: [PantryItem], now: Date = .now) -> Int? {
        guard let lastToss = finished.filter(\.wasTossed).compactMap(\.usedUpDate).max() else { return nil }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: lastToss), to: Calendar.current.startOfDay(for: now)).day
    }

    private func cell(_ v: String, _ l: String, _ icon: String, warn: Bool = false) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon).font(.caption).foregroundStyle(warn ? .orange : .secondary)
            Text(v).font(.system(.headline, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(l).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
}
