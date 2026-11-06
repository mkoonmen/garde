import SwiftUI
import SwiftData

struct SpicesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Spice.name) private var spices: [Spice]
    @State private var adding = false
    @State private var editing: Spice?
    @State private var search = ""

    private var visible: [Spice] { spices.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) } }
    private var needs: [Spice] { spices.filter { $0.level == .low || $0.level == .empty || $0.isStale } }

    var body: some View {
        Group {
            List { Group {
                if !needs.isEmpty && search.isEmpty {
                    Section("Restock or replace") {
                        ForEach(needs) { s in
                            HStack {
                                Text(s.name)
                                Spacer()
                                Text(s.level == .empty ? "Empty" : s.level == .low ? "Low" : "Stale").font(.caption.weight(.semibold))
                                    .foregroundStyle(s.level == .empty ? .red : .orange)
                            }
                        }
                    }
                }
                Section("\(spices.count) on the rack") {
                    if spices.isEmpty {
                        ContentUnavailableView("No spices yet", systemImage: "leaf", description: Text("Tap + to add them, or use Quick add for the common ones."))
                        Button("Quick add 20 common spices", systemImage: "wand.and.stars") { quickAdd() }
                    }
                    ForEach(visible) { s in
                        Button { editing = s } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(s.name).font(.body.weight(.medium))
                                    if !s.shelfSpot.isEmpty { Text(s.shelfSpot).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                LevelGauge(level: s.level)
                            }.contentShape(.rect)
                        }.buttonStyle(.plain)
                        .swipeActions(edge: .leading) {
                            Button("Cook with it", systemImage: "frying.pan") {
                                NotificationRouter.shared.mood = "Something that really shows off \(s.name)"
                                NotificationRouter.shared.tab = 2
                            }.tint(Theme.copper)
                        }
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) { context.delete(s) }
                            Button("Low", systemImage: "arrow.down") { s.level = .low }.tint(.orange)
                            Button("Refilled", systemImage: "arrow.clockwise") { s.level = .full; s.purchaseDate = .now }.tint(.green)
                        }
                    }
                }
            }.listRowBackground(RowGlass()) }
            .gardePage()
            .navigationTitle("Spices")
            .searchable(text: $search)
            .toolbar { Button("Add", systemImage: "plus") { adding = true } }
            .sheet(isPresented: $adding) { SpiceEditView(spice: nil) }
            .sheet(item: $editing) { SpiceEditView(spice: $0) }
        }
    }

    private func quickAdd() {
        ["Black pepper", "Garlic powder", "Onion powder", "Paprika", "Smoked paprika", "Cumin", "Chili powder", "Cayenne",
         "Oregano", "Basil", "Thyme", "Rosemary", "Bay leaves", "Cinnamon", "Nutmeg", "Red pepper flakes",
         "Italian seasoning", "Coriander", "Turmeric", "Kosher salt"].forEach {
            context.insert(Spice(name: $0, isWholeSpice: $0 == "Bay leaves"))
        }
    }
}

struct LevelGauge: View {
    let level: SpiceLevel
    private var filled: Int { switch level { case .full: 3; case .half: 2; case .low: 1; case .empty: 0 } }
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { i in
                Capsule().fill(i < filled ? (filled == 1 ? Color.orange : Theme.accent) : Color.secondary.opacity(0.25)).frame(width: 8, height: 16)
            }
        }.accessibilityLabel(level.label)
    }
}

struct SpiceEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let spice: Spice?
    @State private var name = ""
    @State private var level: SpiceLevel = .full
    @State private var bought = Date()
    @State private var spot = ""
    @State private var whole = false

    var body: some View {
        NavigationStack {
            Form { Group {
                TextField("Name", text: $name)
                Picker("Level", selection: $level) { ForEach(SpiceLevel.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
                DatePicker("Bought or opened", selection: $bought, displayedComponents: .date)
                Toggle("Whole spice (lasts longer)", isOn: $whole)
                TextField("Where it lives (e.g. rack 2, top)", text: $spot)
                if let spice {
                    Section {
                        LabeledContent("Best flavor until", value: spice.bestBy.formatted(date: .abbreviated, time: .omitted))
                        Button("Delete", role: .destructive) { context.delete(spice); dismiss() }
                    }
                }
            }.listRowBackground(RowGlass()) }
            .gardePage()
            .navigationTitle(spice == nil ? "Add spice" : "Edit spice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.isEmpty) }
            }
            .onAppear {
                guard let spice else { return }
                name = spice.name; level = spice.level; bought = spice.purchaseDate; spot = spice.shelfSpot; whole = spice.isWholeSpice
            }
        }
    }

    private func save() {
        let s = spice ?? { let n = Spice(name: name); context.insert(n); return n }()
        s.name = name; s.level = level; s.purchaseDate = bought; s.shelfSpot = spot; s.isWholeSpice = whole
        dismiss()
    }
}
