import SwiftUI
import SwiftData

/// Wine cellar + liquor cabinet, used for pairings.
struct BarView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BarBottle.name) private var bottles: [BarBottle]
    @State private var adding = false
    @State private var editing: BarBottle?

    private var grouped: [(BottleKind, [BarBottle])] {
        let g = Dictionary(grouping: bottles, by: \.kind)
        return BottleKind.allCases.compactMap { k in g[k].map { (k, $0) } }
    }

    var body: some View {
        List {
            if bottles.isEmpty {
                ContentUnavailableView("Bar is empty", systemImage: "wineglass", description: Text("Add your bottles and recipes will pair from what you own."))
            }
            ForEach(grouped, id: \.0) { kind, items in
                Section(kind.label) {
                    ForEach(items) { b in
                        Button { editing = b } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(b.name).font(.body.weight(.medium))
                                    let sub = [b.vintage, b.region].filter { !$0.isEmpty }.joined(separator: " · ")
                                    if !sub.isEmpty { Text(sub).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                Text("×\(b.count)").foregroundStyle(b.count == 0 ? .red : .secondary)
                            }.contentShape(.rect)
                        }.buttonStyle(.plain)
                        .swipeActions {
                            Button("Opened one", systemImage: "minus") { b.count = max(0, b.count - 1) }.tint(.orange)
                            Button("Delete", systemImage: "trash", role: .destructive) { context.delete(b) }
                        }
                    }
                }
            }
        }
        .gardePage()
        .navigationTitle("Bar & cellar")
        .toolbar { Button("Add", systemImage: "plus") { adding = true } }
        .sheet(isPresented: $adding) { BottleEditView(bottle: nil) }
        .sheet(item: $editing) { BottleEditView(bottle: $0) }
    }
}

struct BottleEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let bottle: BarBottle?
    @State private var name = ""
    @State private var kind: BottleKind = .red
    @State private var vintage = ""
    @State private var region = ""
    @State private var count = 1
    @State private var notes = ""
    @State private var photo: Data?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name (e.g. Woodford Reserve Double Oaked)", text: $name)
                Picker("Type", selection: $kind) { ForEach(BottleKind.allCases) { Text($0.label).tag($0) } }
                TextField("Vintage / age", text: $vintage)
                TextField("Region", text: $region)
                Stepper("Bottles: \(count)", value: $count, in: 0...99)
                TextField("Tasting notes", text: $notes, axis: .vertical)
                Section { PhotoField(data: $photo) }
                if let bottle { Button("Delete", role: .destructive) { context.delete(bottle); dismiss() } }
            }
            .gardePage()
            .navigationTitle(bottle == nil ? "Add bottle" : "Edit bottle").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.isEmpty) }
            }
            .onAppear {
                guard let b = bottle else { return }
                name = b.name; kind = b.kind; vintage = b.vintage; region = b.region; count = b.count; notes = b.notes; photo = b.photo
            }
        }
    }

    private func save() {
        let b = bottle ?? { let n = BarBottle(name: name, kind: kind); context.insert(n); return n }()
        b.name = name; b.kind = kind; b.vintage = vintage; b.region = region; b.count = count; b.notes = notes; b.photo = photo
        dismiss()
    }
}
