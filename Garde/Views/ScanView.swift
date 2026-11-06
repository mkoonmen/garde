import SwiftUI
import SwiftData
import PhotosUI

/// Snap a receipt, a grocery haul, a fridge shelf, or a label.
/// Text is read with on-device OCR, then the on-device model turns it into items you review before saving.
struct ScanView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case receipt = "Receipt", groceries = "Groceries", label = "Label", recipe = "Recipe"
        var id: String { rawValue }
        var hint: String {
            switch self {
            case .receipt: "Lay the receipt flat in good light. Long receipts: take it in two photos."
            case .groceries: "Spread items out so labels face the camera."
            case .label: "Get close to the package so the expiration date is sharp."
            case .recipe: "A cookbook page, recipe card or handwritten recipe. Garde reads it and saves it to your recipes."
            }
        }
    }

    @State private var kind: Kind = .receipt
    @State private var image: UIImage?
    @State private var showCamera = false
    @State private var pick: PhotosPickerItem?
    @State private var working = false
    @State private var status = ""
    @State private var review: ScanReviewModel?
    @State private var rawText = ""
    @State private var chef = ChefAI()
    @State private var live = false
    @State private var showInbox = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Button { live = true } label: {
                        HStack {
                            Image(systemName: "barcode.viewfinder").font(.title)
                            VStack(alignment: .leading) {
                                Text("Live scan").font(.headline)
                                Text("Beep through barcodes and dates as you unpack").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }.padding().background(Theme.accent.opacity(0.12), in: .rect(cornerRadius: 14))
                    }.buttonStyle(.plain)

                    Picker("What are you scanning?", selection: $kind) { ForEach(Kind.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented)
                    Text(kind.hint).font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)

                    if let image {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 320).clipShape(.rect(cornerRadius: 14))
                    } else {
                        RoundedRectangle(cornerRadius: 14).fill(.quaternary).frame(height: 220)
                            .overlay { Image(systemName: "doc.viewfinder").font(.system(size: 54)).foregroundStyle(.secondary) }
                    }

                    HStack(spacing: 12) {
                        Button { showCamera = true } label: { Label("Camera", systemImage: "camera.fill").frame(maxWidth: .infinity) }
                            .buttonStyle(GardeProminent()).controlSize(.large)
                        PhotosPicker(selection: $pick, matching: .images) { Label("Photos", systemImage: "photo").frame(maxWidth: .infinity) }
                            .buttonStyle(.bordered).controlSize(.large)
                    }

                    if working { ProgressView(status).padding() }
                    if case .unavailable(let why) = chef.state {
                        Label("\(why) Scans still work with a simpler reader.", systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Label("Everything is read on your iPhone. Nothing is uploaded.", systemImage: "lock.fill")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding()
            }
            .gardePage()
            .navigationTitle("Scan")
            .fullScreenCover(isPresented: $live) { LiveScanView() }
            .navigationDestination(isPresented: $showInbox) { InboxView() }
            .fullScreenCover(isPresented: $showCamera) { CameraPicker { process($0) }.ignoresSafeArea() }
            .onChange(of: pick) { _, new in
                Task {
                    if let raw = try? await new?.loadTransferable(type: Data.self), let img = UIImage(data: raw) { process(img) }
                    pick = nil
                }
            }
            .sheet(item: $review) { model in
                ScanReviewView(scan: model.scan, isReceipt: kind == .receipt, rawText: rawText, image: image) { review = nil; image = nil }
            }
        }
    }

    private func process(_ img: UIImage) {
        if kind == .recipe {
            // Same path as Share → Garde: the inbox reads it, checks allergens and what you'd need to buy.
            RecipeInbox.add(url: nil, text: nil, imageData: img.storageJPEG(maxDimension: 2000))
            showInbox = true
            return
        }
        image = img
        working = true
        Task {
            status = "Reading text…"
            let text = (try? await TextRecognizer.recognizeText(in: img)) ?? ""
            let labels = kind == .receipt ? [] : ((try? await TextRecognizer.classify(img)) ?? [])
            rawText = text
            status = "Figuring out what's what…"
            review = ScanReviewModel(scan: await chef.parseScan(text: text, labels: labels))
            working = false
        }
    }
}

struct ScanReviewModel: Identifiable { let id = UUID(); let scan: ParsedScan }

struct ScanReviewView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State var scan: ParsedScan
    let isReceipt: Bool
    let rawText: String
    let image: UIImage?
    var onDone: () -> Void
    @State private var date = Date()
    @State private var didSave = false
    @State private var saveProblem: String?
    @Query private var existingItems: [PantryItem]
    @Query private var existingReceipts: [Receipt]
    @Query private var profiles: [KitchenProfile]
    private var allergies: [String] { profiles.flatMap(\.allergies) }

    var body: some View {
        NavigationStack {
            Form { Group {
                if isReceipt {
                    Section("Receipt") {
                        TextField("Store", text: $scan.store)
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                        if let total = scan.total { LabeledContent("Total", value: total, format: .currency(code: "USD")) }
                    }
                }
                if let saveProblem { Section { Text(saveProblem).foregroundStyle(.red) } }
                if alreadyImported {
                    Section { Label("This receipt is already in your Kitchen.", systemImage: "checkmark.circle") }
                }
                Section {
                    if scan.items.isEmpty {
                        Text("No food items found. Try a sharper, closer photo, or add items by hand.").foregroundStyle(.secondary)
                    }
                    ForEach($scan.items) { $item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Toggle(isOn: $item.include) { TextField("Name", text: $item.name).font(.body.weight(.medium)) }
                                    .toggleStyle(CheckToggle())
                                Spacer()
                                if let p = item.price { Text(p, format: .currency(code: "USD")).foregroundStyle(.secondary) }
                            }
                            HStack {
                                Picker("", selection: $item.category) { ForEach(FoodCategory.allCases) { Text($0.label).tag($0) } }
                                    .labelsHidden().pickerStyle(.menu)
                                Stepper("\(item.quantity.formatted()) \(item.unit)", value: $item.quantity, in: 0...99, step: 1).font(.caption)
                            }
                            if !isReceipt {
                                Button { item.opened.toggle() } label: {
                                    Label(item.opened ? "Opened" : "Not opened yet", systemImage: item.opened ? "seal.fill" : "seal")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10).padding(.vertical, 4)
                                        .background(item.opened ? Theme.copper.opacity(0.3) : Color.secondary.opacity(0.15), in: .capsule)
                                }.buttonStyle(.plain)
                            }
                            if existingItems.contains(where: { $0.hasStock && (FoodIdentity.productKey($0.name) == FoodIdentity.productKey(item.name) || FoodIdentity.matches(item.name, $0.ingredientName)) }) {
                                Text("Possible existing stock in your Kitchen. Add another package, or skip if it is already counted.").font(.caption).foregroundStyle(.orange)
                                Button("Additional purchase") { item.include = true }.font(.caption)
                                Button("Already counted — skip this item") { item.include = false }.font(.caption)
                            }
                            let hits = AllergenGuard.violations(in: [item.name], allergies: allergies)
                            if !hits.isEmpty {
                                Label("Contains \(hits.joined(separator: ", ")), one of your allergies", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.red)
                            }
                            if let exp = item.printedExpiration {
                                Label("Package date \(exp.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .opacity(item.include ? 1 : 0.4)
                    }
                    .onDelete { scan.items.remove(atOffsets: $0) }
                    Button("Add a missed item", systemImage: "plus") {
                        scan.items.append(ParsedItem(name: "", category: .other, quantity: 1, unit: "each"))
                    }
                } header: { Text("Check these before saving") } footer: {
                    Text("Expiration dates are estimated from typical shelf life unless a package date was read. You can edit any item later.")
                }
            }.listRowBackground(RowGlass()) }
            .gardePage()
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss(); onDone() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(scan.items.filter(\.include).count)") { save() }
                        .disabled(didSave || alreadyImported || (scan.items.filter(\.include).isEmpty && !isReceipt))
                }
            }
        }
    }

    private var alreadyImported: Bool {
        isReceipt && !rawText.isEmpty && existingReceipts.contains { $0.rawText == rawText }
    }

    private func save() {
        guard !didSave && !alreadyImported else { return }
        var receipt: Receipt?
        if isReceipt {
            let r = Receipt(store: scan.store, date: date, total: scan.total, rawText: rawText, image: image?.storageJPEG())
            context.insert(r)
            receipt = r
        }
        for p in scan.items where p.include && !p.name.trimmingCharacters(in: .whitespaces).isEmpty {
            let loc = ShelfLife.defaultLocation(for: p.category, name: p.name)
            let item = PantryItem(name: p.name, category: p.category, location: loc, quantity: p.quantity, unit: p.unit,
                                  purchaseDate: isReceipt ? date : .now,
                                  expirationDate: p.printedExpiration ?? ShelfLife.estimatedExpiration(name: p.name, category: p.category, in: loc, from: isReceipt ? date : .now),
                                  expirationIsEstimated: p.printedExpiration == nil,
                                  price: p.price, store: scan.store.isEmpty ? nil : scan.store)
            if !isReceipt { item.photo = image?.storageJPEG(maxDimension: 600) }
            item.receipt = receipt
            KitchenStock.register(item, context: context)
            if p.opened { item.open() }
        }
        ShoppingBrain.checkOff(names: scan.items.filter { $0.include && !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }.map(\.name), context: context)
        do { try context.save(); didSave = true; dismiss(); onDone() }
        catch { context.rollback(); saveProblem = error.localizedDescription }
    }
}

struct CheckToggle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            Button { configuration.isOn.toggle() } label: {
                Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(configuration.isOn ? Theme.accent : .secondary)
                    .frame(minWidth: 32, minHeight: 32).contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(configuration.isOn ? "Included" : "Excluded")
            .accessibilityAddTraits(.isToggle)
            configuration.label
        }
    }
}
