import SwiftUI
import SwiftData
import Vision
import FoundationModels

/// Wine cellar + liquor cabinet, used for pairings.
struct BarView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BarBottle.name) private var bottles: [BarBottle]
    @State private var adding = false
    @State private var editing: BarBottle?
    @State private var scanning = false
    @State private var reading = false
    @State private var draft: BottleDraft?
    @State private var scanNote: String?

    private var grouped: [(BottleKind, [BarBottle])] {
        let g = Dictionary(grouping: bottles, by: \.kind)
        return BottleKind.allCases.compactMap { k in g[k].map { (k, $0) } }
    }

    var body: some View {
        List { Group {
            if bottles.isEmpty {
                ContentUnavailableView("Bar is empty", systemImage: "wineglass", description: Text("Add your bottles and recipes will pair from what you own."))
            }
            if bottles.contains(where: { $0.count > 0 }) {
                Section {
                    NavigationLink { MixView() } label: { Label("What can I mix tonight?", systemImage: "wineglass.fill") }
                }
            }
            ForEach(grouped, id: \.0) { kind, items in
                Section(kind.label) {
                    ForEach(items) { b in
                        Button { editing = b } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(b.name).font(.body.weight(.medium))
                                    let sub = [b.style, b.format, b.vintage, b.region].filter { !$0.isEmpty }.joined(separator: " · ")
                                    if !sub.isEmpty { Text(sub).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                Text("×\(b.count)").foregroundStyle(b.count == 0 ? .red : .secondary)
                            }.contentShape(.rect)
                        }.buttonStyle(.plain)
                        .swipeActions {
                            Button("Opened one", systemImage: "minus") {
                                let was = b.count
                                b.count = max(0, was - 1)
                                // Last bottle opened: put it on the shopping list (once) so it gets replaced.
                                if was == 1 { context.insert(ShoppingItem(name: b.name, category: .beverages, reason: "Last bottle opened")) }
                            }.tint(.orange)
                            Button("Delete", systemImage: "trash", role: .destructive) { context.delete(b) }
                        }
                    }
                }
            }
        }.listRowBackground(RowGlass()) }
        .gardePage()
        .navigationTitle("Bar & cellar")
        .toolbar {
            ToolbarItemGroup {
                Button("Scan bottle", systemImage: "camera.viewfinder") { scanning = true }
                Button("Add", systemImage: "plus") { adding = true }
            }
        }
        .safeAreaInset(edge: .top) {
            if reading {
                HStack { ProgressView(); Text("Reading the label…") }.padding(10).background(.ultraThinMaterial, in: .capsule)
            } else if let scanNote {
                Text(scanNote).font(.footnote).padding(10).background(.ultraThinMaterial, in: .capsule)
            }
        }
        .fullScreenCover(isPresented: $scanning) {
            CameraPicker { img in
                reading = true; scanNote = nil
                Task {
                    draft = await BottleReader.read(img)
                    reading = false
                    if draft == nil { scanNote = "Couldn't read that label. Try closer, with the front label filling the frame." }
                }
            }.ignoresSafeArea()
        }
        .sheet(item: $draft) { BottleEditView(bottle: nil, prefill: $0) }
        .sheet(isPresented: $adding) { BottleEditView(bottle: nil) }
        .sheet(item: $editing) { BottleEditView(bottle: $0) }
    }
}

struct BottleEditView: View {
    @Environment(\.modelContext) private var context
    @Query private var allBottles: [BarBottle]
    @Environment(\.dismiss) private var dismiss
    let bottle: BarBottle?
    var prefill: BottleDraft? = nil
    @State private var name = ""
    @State private var kind: BottleKind = .red
    @State private var category: DrinkCategory = .wine
    @State private var style = ""
    @State private var format = ""
    @State private var vintage = ""
    @State private var region = ""
    @State private var count = 1
    @State private var notes = ""
    @State private var photo: Data?

    var body: some View {
        NavigationStack {
            Form { Group {
                TextField("Name (e.g. Woodford Reserve Double Oaked)", text: $name)
                Picker("Drink", selection: $category) { ForEach(DrinkCategory.allCases) { Text($0.label).tag($0) } }
                    .onChange(of: category) { _, c in if kind.category != c { kind = c.kinds.first ?? .other; style = "" } }
                if category != .other {
                    Picker("Type", selection: $kind) { ForEach(category.kinds) { Text($0.label).tag($0) } }
                        .onChange(of: kind) { _, k in if !k.styles.contains(style) { style = "" } }
                }
                if !kind.styles.isEmpty {
                    Picker("Style", selection: $style) {
                        Text("Not sure").tag("")
                        ForEach(kind.styles, id: \.self) { Text($0).tag($0) }
                    }
                }
                if kind.hasFormat {
                    Picker("Comes in", selection: $format) {
                        Text("—").tag("")
                        ForEach(BottleKind.formats, id: \.self) { Text($0).tag($0) }
                    }
                }
                TextField("Vintage / age", text: $vintage)
                TextField("Region", text: $region)
                Stepper("\(kind.hasFormat ? "How many" : "Bottles"): \(count)", value: $count, in: 0...99)
                TextField("Tasting notes", text: $notes, axis: .vertical)
                Section { PhotoField(data: $photo) }
                if let bottle { Button("Delete", role: .destructive) { context.delete(bottle); dismiss() } }
            }.listRowBackground(RowGlass()) }
            .gardePage()
            .navigationTitle(bottle == nil ? "Add bottle" : "Edit bottle").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.isEmpty) }
            }
            .onAppear {
                if let p = prefill {
                    name = p.name; kind = p.kind; category = p.kind.category; vintage = p.vintage; region = p.region; notes = p.notes; photo = p.photo
                    if let existing = existingMatch(p.name) { name = existing.name; count = existing.count + 1 }
                    return
                }
                guard let b = bottle else { return }
                name = b.name; kind = b.kind; category = b.kind.category; style = b.style; format = b.format; vintage = b.vintage; region = b.region; count = b.count; notes = b.notes; photo = b.photo
            }
        }
    }

    private func existingMatch(_ n: String) -> BarBottle? {
        allBottles.first { $0.name.caseInsensitiveCompare(n) == .orderedSame }
    }

    private func save() {
        // Scanning a bottle you already have adds to its count instead of making a duplicate.
        let b = bottle ?? (prefill != nil ? existingMatch(name) : nil) ?? { let n = BarBottle(name: name, kind: kind); context.insert(n); return n }()
        b.name = name; b.kind = kind; b.style = style; b.format = format; b.vintage = vintage; b.region = region; b.count = count; b.notes = notes; b.photo = photo
        dismiss()
    }
}



/// What a label scan found, ready to review before saving.
struct BottleDraft: Identifiable {
    let id = UUID()
    var name: String
    var kind: BottleKind
    var vintage: String
    var region: String
    var notes: String
    var photo: Data?
}

/// Reads a bottle photo on the iPhone: barcode (looked up in Open Food Facts) + label text,
/// then the on-device model turns it into producer/name, type, vintage and region.
@MainActor
enum BottleReader {
    @Generable
    struct Label {
        @Guide(description: "Full bottle name as a person would say it, producer first, e.g. 'Woodford Reserve Double Oaked' or 'Caymus Cabernet Sauvignon'")
        var name: String
        @Guide(description: "One of: red, white, rose, sparkling, dessert, orangeWine, fortified, bourbon, rye, scotch, irish, japanese, whiskey, tequila, mezcal, rum, gin, vodka, cognac, brandy, liqueur, amaro, vermouth, absinthe, sake, soju, bitters, lager, pilsner, ipa, paleAle, wheat, stout, porter, amber, belgian, sour, cider, nonAlcBeer, seltzer, cannedCocktail, other")
        var kind: String
        @Guide(description: "Vintage year or age statement like '12 Year', or empty")
        var vintage: String
        @Guide(description: "Region or country, e.g. 'Napa Valley' or 'Kentucky', or empty")
        var region: String
        @Guide(description: "Grape, proof/ABV or style worth noting, short, or empty")
        var notes: String
    }

    static func read(_ image: UIImage) async -> BottleDraft? {
        let text = (try? await TextRecognizer.recognizeText(in: image)) ?? ""
        let code = await barcode(in: image)
        var hint = ""
        if let code, let p = await BarcodeLookup.lookup(code) { hint = [p.brand, p.name, p.size].filter { !$0.isEmpty }.joined(separator: " ") }
        guard !(text + hint).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let photo = image.storageJPEG(maxDimension: 900)

        if SystemLanguageModel.default.availability == .available || ChefEngine.shared.usingLocal {
            let session = ChefEngine.shared.session(instructions: "You read wine, liquor, beer and seltzer labels. Use only what's on the label; don't invent a vintage.")
            if let l = try? await session.respond(to: """
            Product database match: \(hint.isEmpty ? "none" : hint)
            Label text:
            \(String(text.prefix(1500)))
            """, generating: Label.self).content, !l.name.isEmpty {
                return BottleDraft(name: l.name, kind: BottleKind.allCases.first { $0.rawValue.lowercased() == l.kind.lowercased() } ?? guessKind(text + hint),
                                   vintage: l.vintage, region: l.region, notes: l.notes, photo: photo)
            }
        }
        // Without the AI: use the database name or the biggest lines of label text.
        let name = hint.isEmpty ? text.split(separator: "\n").prefix(2).joined(separator: " ") : hint
        let year = text.firstMatch(of: /\b(19[5-9]\d|20[0-3]\d)\b/).map { String($0.1) } ?? ""
        return BottleDraft(name: name, kind: guessKind(text + hint), vintage: year, region: "", notes: "", photo: photo)
    }

    static func guessKind(_ s: String) -> BottleKind {
        let t = s.lowercased()
        let map: [(BottleKind, [String])] = [
            (.seltzer, ["hard seltzer", "seltzer", "white claw", "truly"]), (.cannedCocktail, ["canned cocktail", "ready to drink", "high noon", "cutwater"]),
            (.nonAlcBeer, ["non-alcoholic", "non alcoholic", "0.0%", "athletic brewing"]),
            (.ipa, ["ipa", "india pale"]), (.stout, ["stout"]), (.porter, ["porter"]), (.sour, ["sour", "gose"]),
            (.wheat, ["hefeweizen", "witbier", "wheat"]), (.pilsner, ["pilsner", "pils"]), (.cider, ["cider", "perry"]),
            (.belgian, ["tripel", "dubbel", "saison", "trappist"]), (.paleAle, ["pale ale"]), (.lager, ["lager", "helles", "märzen", "bock"]),
            (.bourbon, ["bourbon"]), (.scotch, ["scotch", "single malt", "islay", "speyside"]), (.irish, ["irish whiskey"]),
            (.japanese, ["japanese whisky", "suntory", "nikka"]), (.rye, ["rye whiskey", " rye"]), (.whiskey, ["whiskey", "whisky"]),
            (.mezcal, ["mezcal"]), (.tequila, ["tequila", "reposado", "añejo", "blanco"]),
            (.cognac, ["cognac", "armagnac", "vsop"]), (.brandy, ["brandy", "pisco", "calvados", "grappa"]),
            (.vermouth, ["vermouth", "lillet"]), (.amaro, ["amaro", "campari", "aperol", "fernet", "chartreuse"]),
            (.liqueur, ["liqueur", "triple sec", "cointreau", "kahlua", "baileys"]), (.absinthe, ["absinthe"]), (.sake, ["sake", "junmai"]),
            (.rum, ["rum"]), (.gin, ["gin"]), (.vodka, ["vodka"]),
            (.sparkling, ["champagne", "prosecco", "cava", "brut", "sparkling", "crémant"]), (.rose, ["rosé", "rose"]),
            (.fortified, ["port", "sherry", "madeira", "marsala"]), (.dessert, ["sauternes", "late harvest", "ice wine"]),
            (.white, ["chardonnay", "sauvignon blanc", "pinot grigio", "riesling", "white"]),
            (.red, ["cabernet", "merlot", "pinot noir", "malbec", "zinfandel", "syrah", "red", "chianti", "rioja", "bordeaux"]),
            (.lager, ["beer"]),
        ]
        return map.first { $0.1.contains(where: { t.contains($0) }) }?.0 ?? .other
    }

    static func barcode(in image: UIImage) async -> String? {
        guard let cg = image.cgImage else { return nil }
        let orientation = image.cgOrientation
        return await Task.detached {
            let req = VNDetectBarcodesRequest()
            try? VNImageRequestHandler(cgImage: cg, orientation: orientation).perform([req])
            return req.results?.first?.payloadStringValue
        }.value
    }
}
