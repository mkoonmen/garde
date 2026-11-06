import SwiftUI
import SwiftData
import PhotosUI
import FoundationModels

/// Snap the fridge (or freezer/pantry). Garde compares the photo with what it thinks is in there,
/// then asks only about what seems to be gone: ate it, tossed it, or still there.
struct FridgeCheckView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<PantryItem> { !$0.isUsedUp }) private var items: [PantryItem]

    @State private var location: StorageLocation = .fridge
    @State private var image: UIImage?
    @State private var showCamera = false
    @State private var pick: PhotosPickerItem?
    @State private var working = false
    @State private var verdicts: [UUID: Verdict] = [:]
    @State private var seen: Set<UUID> = []
    @State private var checked = false
    @State private var note: String?

    enum Verdict: String, CaseIterable { case stillThere = "Still there", ate = "Ate it", tossed = "Tossed" }

    private var inSpot: [PantryItem] { items.filter { $0.location == location } }
    private var missing: [PantryItem] { inSpot.filter { !seen.contains($0.id) } }

    var body: some View {
        List { Group {
            Section {
                Picker("Where", selection: $location) {
                    ForEach([StorageLocation.fridge, .freezer, .pantry]) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented)
                if let image {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 260).clipShape(.rect(cornerRadius: 12))
                }
                HStack {
                    Button("Take photo", systemImage: "camera.fill") { showCamera = true }.buttonStyle(GardeProminent())
                    Spacer()
                    PhotosPicker(selection: $pick, matching: .images) { Label("Library", systemImage: "photo") }
                }
                if working { HStack { ProgressView(); Text("Looking…").foregroundStyle(.secondary) } }
            } footer: {
                Text("Open the door and get as much in frame as you can. Garde only asks about things it doesn't see. Read on this iPhone.")
            }

            if checked {
                if missing.isEmpty {
                    Section { Label("Everything Garde expected is there.", systemImage: "checkmark.seal.fill").foregroundStyle(.green) }
                } else {
                    Section {
                        ForEach(missing) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.name).font(.body.weight(.medium))
                                Picker("", selection: Binding(get: { verdicts[item.id] ?? .stillThere }, set: { verdicts[item.id] = $0 })) {
                                    ForEach(Verdict.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                                }.pickerStyle(.segmented)
                            }
                        }
                        Button("Update kitchen") { apply() }.buttonStyle(GardeProminent()).frame(maxWidth: .infinity)
                    } header: { Text("Didn't spot these") }
                }
                if !seen.isEmpty {
                    Section("Spotted") {
                        ForEach(inSpot.filter { seen.contains($0.id) }) { Text($0.name).foregroundStyle(.secondary) }
                    }
                }
            }
            if let note { Section { Text(note) } }
        }.listRowBackground(RowGlass()) }
        .gardePage()
        .navigationTitle("Fridge check-in")
        .fullScreenCover(isPresented: $showCamera) { CameraPicker { analyze($0) }.ignoresSafeArea() }
        .onChange(of: pick) { _, new in
            Task {
                if let raw = try? await new?.loadTransferable(type: Data.self), let img = UIImage(data: raw) { analyze(img) }
                pick = nil
            }
        }
        .onChange(of: location) { _, _ in checked = false; seen = []; verdicts = [:] }
    }

    @Generable
    struct Sighting {
        @Guide(description: "Exact names from the inventory list that are visible or very likely visible in the photo")
        var visible: [String]
    }

    private func analyze(_ img: UIImage) {
        image = img; working = true; checked = false; note = nil
        Task {
            defer { working = false }
            let labels = (try? await TextRecognizer.classify(img, minConfidence: 0.15)) ?? []
            let text = (try? await TextRecognizer.recognizeText(in: img)) ?? ""
            let names = inSpot.map(\.name)
            var visible: Set<String> = []
            // Fast match: OCR'd label text and recognized objects.
            let hay = (labels + [text]).joined(separator: " ").lowercased()
            for item in inSpot where ShoppingBrain.appears(item.name, in: hay) { visible.insert(item.name) }
            // Then let the on-device model reason about the rest.
            if SystemLanguageModel.default.availability == .available || ChefEngine.shared.usingLocal, !names.isEmpty {
                let session = ChefEngine.shared.session(instructions: "You compare a kitchen inventory with what a camera saw in a fridge photo. Be generous: if an item could plausibly be one of the seen objects or text, count it as visible.")
                if let r = try? await session.respond(to: """
                Inventory: \(names.joined(separator: "; "))
                Objects recognized in the photo: \(labels.joined(separator: ", "))
                Text read from packages: \(String(text.prefix(1500)))
                """, generating: Sighting.self).content {
                    r.visible.forEach { visible.insert($0) }
                }
            }
            let lowered = Set(visible.map { $0.lowercased() })
            seen = Set(inSpot.filter { lowered.contains($0.name.lowercased()) }.map(\.id))
            checked = true
        }
    }

    private func apply() {
        var ate = 0, tossed = 0
        for item in missing {
            switch verdicts[item.id] ?? .stillThere {
            case .ate: item.markUsed(); ate += 1
            case .tossed: item.markUsed(tossed: true); tossed += 1
            case .stillThere: break
            }
        }
        note = "Updated: \(ate) eaten, \(tossed) tossed."
        UserDefaults.standard.set(Date.now, forKey: "fridgeCheck.last")
        checked = false; verdicts = [:]
    }
}
