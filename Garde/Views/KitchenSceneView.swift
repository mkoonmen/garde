import SwiftUI
import SwiftData

// MARK: - Food icons

/// A colorful emoji for any food, by name first (lemon, salmon…) then by category.
enum FoodIcon {
    static let byName: [(String, String)] = [
        ("lemon", "🍋"), ("lime", "🍋"), ("avocado", "🥑"), ("banana", "🍌"), ("apple", "🍎"), ("pear", "🍐"), ("orange", "🍊"),
        ("grape", "🍇"), ("strawberr", "🍓"), ("blueberr", "🫐"), ("cherr", "🍒"), ("peach", "🍑"), ("mango", "🥭"), ("pineapple", "🍍"),
        ("watermelon", "🍉"), ("coconut", "🥥"), ("tomato", "🍅"), ("eggplant", "🍆"), ("potato", "🥔"), ("carrot", "🥕"), ("corn", "🌽"),
        ("pepper", "🫑"), ("jalape", "🌶️"), ("cucumber", "🥒"), ("lettuce", "🥬"), ("spinach", "🥬"), ("kale", "🥬"), ("arugula", "🥬"),
        ("broccoli", "🥦"), ("garlic", "🧄"), ("onion", "🧅"), ("shallot", "🧅"), ("mushroom", "🍄"), ("ginger", "🫚"), ("pea", "🫛"),
        ("bean", "🫘"), ("chickpea", "🫘"), ("peanut", "🥜"), ("almond", "🌰"), ("hazelnut", "🌰"), ("chestnut", "🌰"),
        ("egg", "🥚"), ("milk", "🥛"), ("cream", "🥛"), ("yogurt", "🥛"), ("butter", "🧈"), ("cheese", "🧀"), ("mozzarella", "🧀"),
        ("parmesan", "🧀"), ("brie", "🧀"), ("cheddar", "🧀"), ("boursin", "🧀"), ("bacon", "🥓"), ("steak", "🥩"), ("ribeye", "🥩"),
        ("beef", "🥩"), ("pork", "🥩"), ("lamb", "🥩"), ("chicken", "🍗"), ("turkey", "🍗"), ("wing", "🍗"), ("shrimp", "🦐"),
        ("lobster", "🦞"), ("crab", "🦀"), ("oyster", "🦪"), ("clam", "🦪"), ("squid", "🦑"), ("salmon", "🐟"), ("tuna", "🐟"),
        ("fish", "🐟"), ("cod", "🐟"), ("sausage", "🌭"), ("hot dog", "🌭"), ("ham", "🍖"), ("bread", "🍞"), ("bagel", "🥯"),
        ("baguette", "🥖"), ("croissant", "🥐"), ("tortilla", "🫓"), ("pita", "🫓"), ("pancake", "🥞"), ("waffle", "🧇"), ("pasta", "🍝"),
        ("spaghetti", "🍝"), ("noodle", "🍜"), ("ramen", "🍜"), ("rice", "🍚"), ("dumpling", "🥟"), ("pizza", "🍕"), ("taco", "🌮"),
        ("burrito", "🌯"), ("sushi", "🍣"), ("soup", "🥣"), ("broth", "🥣"), ("stock", "🥣"), ("salt", "🧂"), ("honey", "🍯"),
        ("jam", "🍯"), ("chocolate", "🍫"), ("cookie", "🍪"), ("cake", "🍰"), ("ice cream", "🍨"), ("popcorn", "🍿"), ("chips", "🥔"),
        ("pretzel", "🥨"), ("cracker", "🍘"), ("coffee", "☕️"), ("tea", "🫖"), ("juice", "🧃"), ("soda", "🥤"), ("seltzer", "🥤"),
        ("water", "💧"), ("wine", "🍷"), ("beer", "🍺"), ("bourbon", "🥃"), ("whiskey", "🥃"), ("oil", "🫒"), ("olive", "🫒"),
        ("sauce", "🥫"), ("can", "🥫"), ("ketchup", "🥫"), ("mustard", "🥫"), ("tofu", "🧊"), ("ice", "🧊"),
    ]
    static func of(_ item: PantryItem) -> String {
        if item.isLeftover { return "🍱" }
        let n = item.name.lowercased()
        if let hit = byName.first(where: { n.contains($0.0) }) { return hit.1 }
        switch item.category {
        case .meat: return "🥩"; case .poultry: return "🍗"; case .seafood: return "🐟"; case .dairy: return "🥛"
        case .cheese: return "🧀"; case .eggs: return "🥚"; case .produce: return "🥬"; case .fruit: return "🍎"
        case .bakery: return "🍞"; case .grains: return "🌾"; case .canned: return "🥫"; case .condiments: return "🫙"
        case .frozen: return "🧊"; case .beverages: return "🧃"; case .snacks: return "🍿"; case .deli: return "🥪"; case .other: return "🍽️"
        }
    }
}

// MARK: - The kitchen

/// The Kitchen tab: an illustrated kitchen. Tap the fridge, freezer, pantry, counter, spice rack or wine rack
/// and its door swings open into that space.
struct KitchenSceneView: View {
    @Query(filter: #Predicate<PantryItem> { !$0.isUsedUp }) private var items: [PantryItem]
    @Query private var spices: [Spice]
    @Query private var bottles: [BarBottle]
    @State private var opening: Zone?
    @State private var path: [Zone] = []
    @State private var showList = false

    enum Zone: Hashable { case fridge, freezer, pantry, counter, spices, bar }

    private func count(_ loc: StorageLocation) -> Int { items.filter { $0.location == loc }.count }
    private func expiring(_ loc: StorageLocation) -> Int { items.filter { $0.location == loc && ($0.daysLeft ?? 99) <= 2 }.count }

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .bottom) {
                    KitchenWall()
                    VStack(spacing: 0) {
                        header.padding(.top, 8)
                        Spacer(minLength: 8)
                        // Wall: spice rack + wine rack
                        HStack(alignment: .bottom, spacing: 14) {
                            Button { tap(.spices) } label: { SpiceRackArt(count: spices.count, low: spices.filter { $0.level == .low || $0.level == .empty }.count) }
                            Spacer()
                            Button { tap(.bar) } label: { WineRackArt(count: bottles.reduce(0) { $0 + $1.count }) }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                        Spacer(minLength: 10)
                        // Appliances
                        HStack(alignment: .bottom, spacing: 12) {
                            VStack(spacing: 4) {
                                Button { tap(.fridge) } label: {
                                    FridgeDoorArt(count: count(.fridge), expiring: expiring(.fridge), open: opening == .fridge)
                                }
                                Button { tap(.freezer) } label: {
                                    FreezerDrawerArt(count: count(.freezer), expiring: expiring(.freezer), open: opening == .freezer)
                                }
                            }
                            .frame(width: w * 0.38)
                            VStack(spacing: 10) {
                                Button { tap(.pantry) } label: {
                                    PantryArt(count: count(.pantry), expiring: expiring(.pantry), open: opening == .pantry)
                                }
                                Button { tap(.counter) } label: {
                                    CounterArt(count: count(.counter), expiring: expiring(.counter))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        KitchenFloor().frame(height: 46)
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("List view", systemImage: "list.bullet") { showList = true }
                }
            }
            .navigationDestination(for: Zone.self) { zone in
                switch zone {
                case .fridge: ZoneView(location: .fridge)
                case .freezer: ZoneView(location: .freezer)
                case .pantry: ZoneView(location: .pantry)
                case .counter: ZoneView(location: .counter)
                case .spices: SpicesView()
                case .bar: BarView()
                }
            }
            .sheet(isPresented: $showList) { InventoryView() }
            .sensoryFeedback(.impact(weight: .medium), trigger: opening)
        }
    }

    private var header: some View {
        let soon = items.filter { ($0.daysLeft ?? 99) <= 2 }.count
        return VStack(spacing: 2) {
            Text(greeting).font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
            Text(soon == 0 ? "Everything's fresh" : "\(soon) thing\(soon == 1 ? "" : "s") to use soon")
                .font(.system(.title2, design: .serif).weight(.bold)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            Text("Tap the fridge, freezer or pantry").font(.caption).foregroundStyle(.white.opacity(0.7))
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"; case 12..<17: "Good afternoon"; default: "Good evening"
        }
    }

    /// Swing the door open, then walk in.
    private func tap(_ zone: Zone) {
        withAnimation(.spring(duration: 0.45, bounce: 0.25)) { opening = zone }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            path.append(zone)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { opening = nil }
        }
    }
}

// MARK: - Scenery

struct KitchenWall: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.13, green: 0.20, blue: 0.42), Color(red: 0.08, green: 0.12, blue: 0.29)],
                           startPoint: .top, endPoint: .bottom)
            // Subway-tile backsplash
            Canvas { ctx, size in
                let tw: CGFloat = 34, th: CGFloat = 17
                var row = 0
                var y: CGFloat = 0
                while y < size.height {
                    var x: CGFloat = row.isMultiple(of: 2) ? 0 : -tw / 2
                    while x < size.width {
                        let r = CGRect(x: x + 1, y: y + 1, width: tw - 2, height: th - 2)
                        ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(.white.opacity(0.045)))
                        x += tw
                    }
                    y += th; row += 1
                }
            }
            // Warm pendant-light glow
            RadialGradient(colors: [Color(red: 1, green: 0.78, blue: 0.45).opacity(0.35), .clear], center: .init(x: 0.5, y: 0.08),
                           startRadius: 0, endRadius: 320)
        }
        .ignoresSafeArea()
    }
}

struct KitchenFloor: View {
    var body: some View {
        Canvas { ctx, size in
            let colors = [Color(red: 0.55, green: 0.36, blue: 0.22), Color(red: 0.49, green: 0.31, blue: 0.19), Color(red: 0.60, green: 0.40, blue: 0.25)]
            var x: CGFloat = 0, i = 0
            while x < size.width {
                let w: CGFloat = 46
                ctx.fill(Path(CGRect(x: x, y: 0, width: w - 1.5, height: size.height)), with: .color(colors[i % 3]))
                x += w; i += 1
            }
            ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: 4)), with: .color(.black.opacity(0.35)))
        }
    }
}

/// Little count badge stuck on an appliance like a fridge magnet.
struct Magnet: View {
    let count: Int
    let expiring: Int
    var body: some View {
        HStack(spacing: 4) {
            Text("\(count)").font(.system(.headline, design: .rounded).weight(.heavy))
            if expiring > 0 {
                Text("\(expiring)⚠︎").font(.caption2.weight(.bold)).padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.orange, in: .capsule).foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Color(red: 0.95, green: 0.33, blue: 0.30), in: .capsule)
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.3), radius: 2, y: 2)
        .rotationEffect(.degrees(-6))
    }
}

struct FridgeDoorArt: View {
    let count: Int, expiring: Int, open: Bool
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Glowing interior visible when the door swings
            RoundedRectangle(cornerRadius: 18).fill(LinearGradient(colors: [.white, Color(red: 0.82, green: 0.92, blue: 1)], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(colors: [Color(red: 0.86, green: 0.89, blue: 0.93), Color(red: 0.68, green: 0.72, blue: 0.79)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(alignment: .trailing) {
                    Capsule().fill(Color(red: 0.55, green: 0.58, blue: 0.64)).frame(width: 7, height: 70).padding(.trailing, 10)
                }
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.6), lineWidth: 1.5))
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 6) {
                        Magnet(count: count, expiring: expiring)
                        Text("FRIDGE").font(.caption2.weight(.heavy)).tracking(2).foregroundStyle(.black.opacity(0.35))
                    }.padding(12)
                }
                .rotation3DEffect(.degrees(open ? -80 : 0), axis: (0, 1, 0), anchor: .leading, perspective: 0.5)
        }
        .frame(height: 230)
        .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
    }
}

struct FreezerDrawerArt: View {
    let count: Int, expiring: Int, open: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(LinearGradient(colors: [Color(red: 0.80, green: 0.86, blue: 0.93), Color(red: 0.62, green: 0.69, blue: 0.79)], startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .top) { Capsule().fill(Color(red: 0.52, green: 0.56, blue: 0.63)).frame(width: 70, height: 7).padding(.top, 10) }
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.6), lineWidth: 1.5))
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 6) {
                    Magnet(count: count, expiring: expiring)
                    Text("❄︎ FREEZER").font(.caption2.weight(.heavy)).tracking(1.5).foregroundStyle(Color(red: 0.2, green: 0.4, blue: 0.7).opacity(0.7))
                }.padding(10)
            }
            .frame(height: 96)
            .offset(y: open ? 22 : 0)
            .scaleEffect(open ? 1.04 : 1)
            .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
    }
}

struct PantryArt: View {
    let count: Int, expiring: Int, open: Bool
    private let wood = Color(red: 0.62, green: 0.40, blue: 0.24)
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.28, green: 0.18, blue: 0.10))   // inside
            HStack(spacing: 3) {
                door(leading: true).rotation3DEffect(.degrees(open ? -75 : 0), axis: (0, 1, 0), anchor: .leading, perspective: 0.5)
                door(leading: false).rotation3DEffect(.degrees(open ? 75 : 0), axis: (0, 1, 0), anchor: .trailing, perspective: 0.5)
            }
            VStack {
                Magnet(count: count, expiring: expiring)
                Text("PANTRY").font(.caption2.weight(.heavy)).tracking(2).foregroundStyle(.white.opacity(0.75))
            }.opacity(open ? 0 : 1)
        }
        .frame(height: 210)
        .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
    }
    private func door(leading: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(LinearGradient(colors: [wood, wood.opacity(0.8)], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.black.opacity(0.18), lineWidth: 2).padding(10))
            .overlay(alignment: leading ? .trailing : .leading) {
                Circle().fill(Color(red: 0.92, green: 0.78, blue: 0.45)).frame(width: 10).padding(8)
            }
    }
}

struct CounterArt: View {
    let count: Int, expiring: Int
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 4) {
                Text("🍌🍎🍋").font(.title3)
                Spacer()
                Magnet(count: count, expiring: expiring)
            }.padding(.horizontal, 8).padding(.bottom, 2)
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [Color(red: 0.86, green: 0.70, blue: 0.48), Color(red: 0.72, green: 0.55, blue: 0.35)], startPoint: .top, endPoint: .bottom))
                .frame(height: 18)
                .overlay(Text("COUNTER").font(.system(size: 8, weight: .heavy)).tracking(2).foregroundStyle(.black.opacity(0.35)))
        }
        .shadow(color: .black.opacity(0.3), radius: 6, y: 4)
    }
}

struct SpiceRackArt: View {
    let count: Int, low: Int
    private let jarColors: [Color] = [.red, .orange, .yellow, .green, .brown, .pink]
    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<6, id: \.self) { i in
                    VStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 2).fill(.black.opacity(0.6)).frame(width: 12, height: 4)
                        RoundedRectangle(cornerRadius: 3).fill(jarColors[i].opacity(0.85)).frame(width: 14, height: 22)
                    }
                }
            }
            RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.55, green: 0.36, blue: 0.22)).frame(width: 118, height: 6)
            Text(low > 0 ? "Spices · \(low) low" : "Spices · \(count)").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.85))
        }
    }
}

struct WineRackArt: View {
    let count: Int
    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.40, green: 0.24, blue: 0.14)).frame(width: 84, height: 54)
                Grid(horizontalSpacing: 5, verticalSpacing: 5) {
                    ForEach(0..<2, id: \.self) { _ in
                        GridRow {
                            ForEach(0..<3, id: \.self) { j in
                                Circle().fill(j == 1 ? Color(red: 0.9, green: 0.85, blue: 0.6) : Color(red: 0.45, green: 0.05, blue: 0.12))
                                    .frame(width: 16, height: 16).overlay(Circle().strokeBorder(.black.opacity(0.4)))
                            }
                        }
                    }
                }
            }
            Text("Bar · \(count)").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.85))
        }
    }
}

// MARK: - Inside the fridge / freezer / pantry / counter

struct ZoneView: View {
    let location: StorageLocation
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<PantryItem> { !$0.isUsedUp }) private var all: [PantryItem]
    @State private var editing: PantryItem?
    @State private var adding = false
    @State private var appeared = false

    private var items: [PantryItem] { all.filter { $0.location == location }.sorted { ($0.daysLeft ?? 999) < ($1.daysLeft ?? 999) } }

    /// Shelves for each space, so things land where you'd expect.
    private var shelves: [(String, [PantryItem])] {
        func pick(_ cats: Set<FoodCategory>) -> [PantryItem] { items.filter { cats.contains($0.category) || ($0.isLeftover && cats.contains(.other)) } }
        switch location {
        case .fridge:
            let used: Set<FoodCategory> = [.dairy, .cheese, .eggs, .deli, .meat, .poultry, .seafood, .produce, .fruit, .condiments, .beverages]
            return [("Top shelf · dairy & eggs", pick([.dairy, .cheese, .eggs])),
                    ("Middle shelf · leftovers & deli", pick([.deli]) + items.filter(\.isLeftover)),
                    ("Meat & seafood drawer", pick([.meat, .poultry, .seafood])),
                    ("Crisper · fruit & veg", pick([.produce, .fruit])),
                    ("Door · sauces & drinks", pick([.condiments, .beverages])),
                    ("Everything else", items.filter { !used.contains($0.category) && !$0.isLeftover })]
        case .freezer:
            return [("Top basket", items.filter { [.meat, .poultry, .seafood].contains($0.category) }),
                    ("Bottom basket", items.filter { ![.meat, .poultry, .seafood].contains($0.category) })]
        case .pantry:
            return [("Top shelf · grains & baking", items.filter { [.grains, .bakery].contains($0.category) }),
                    ("Middle shelf · cans & jars", items.filter { [.canned, .condiments].contains($0.category) }),
                    ("Bottom shelf · snacks & drinks", items.filter { [.snacks, .beverages].contains($0.category) }),
                    ("Everything else", items.filter { ![.grains, .bakery, .canned, .condiments, .snacks, .beverages].contains($0.category) })]
        case .counter:
            return [("On the counter", items)]
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if items.isEmpty {
                    VStack(spacing: 8) {
                        Text(style.emptyEmoji).font(.system(size: 64))
                        Text("Nothing in the \(location.label.lowercased()) yet").font(.headline)
                        Text("Scan a receipt or tap + to add food.").font(.subheadline).foregroundStyle(style.secondary)
                    }.padding(.top, 60)
                }
                ForEach(Array(shelves.enumerated()), id: \.offset) { idx, shelf in
                    if !shelf.1.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(shelf.0.uppercased()).font(.caption2.weight(.heavy)).tracking(1.2).foregroundStyle(style.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .bottom, spacing: 10) {
                                    ForEach(shelf.1) { item in
                                        Button { editing = item } label: { FoodChip(item: item, style: style) }.buttonStyle(.plain)
                                            .contextMenu {
                                                Button("Ate it", systemImage: "checkmark") { item.markUsed() }
                                                Button("Tossed", systemImage: "trash") { item.markUsed(tossed: true) }
                                                if item.canFreeze { Button("Freeze", systemImage: "snowflake") { item.freeze() } }
                                                if item.location == .freezer { Button("Thaw", systemImage: "drop") { item.thaw() } }
                                            }
                                    }
                                }.padding(.horizontal, 4).padding(.bottom, 6)
                            }
                            style.shelf.frame(height: 8).clipShape(.rect(cornerRadius: 4))
                                .shadow(color: .black.opacity(0.25), radius: 3, y: 3)
                        }
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(.spring(duration: 0.5).delay(Double(idx) * 0.06), value: appeared)
                    }
                }
            }
            .padding()
        }
        .background { style.background.ignoresSafeArea() }
        .overlay { if location == .freezer { FrostOverlay().allowsHitTesting(false) } }
        .navigationTitle(location.label)
        .toolbar { Button("Add", systemImage: "plus") { adding = true } }
        .sheet(item: $editing) { ItemEditView(item: $0) }
        .sheet(isPresented: $adding) { ItemEditView(item: nil) }
        .onAppear { appeared = true }
    }

    private var style: ZoneStyle { ZoneStyle.of(location) }
}

struct ZoneStyle {
    var background: AnyView
    var shelf: AnyView
    var card: Color
    var secondary: Color
    var emptyEmoji: String

    static func of(_ loc: StorageLocation) -> ZoneStyle {
        switch loc {
        case .fridge:
            return ZoneStyle(
                background: AnyView(LinearGradient(colors: [Color(red: 0.93, green: 0.97, blue: 1), Color(red: 0.78, green: 0.88, blue: 0.98)], startPoint: .top, endPoint: .bottom)
                    .overlay(RadialGradient(colors: [.white, .clear], center: .top, startRadius: 0, endRadius: 300))),
                shelf: AnyView(LinearGradient(colors: [.white.opacity(0.9), Color(red: 0.7, green: 0.85, blue: 0.95).opacity(0.8)], startPoint: .top, endPoint: .bottom)),
                card: .white, secondary: Color(red: 0.25, green: 0.4, blue: 0.6), emptyEmoji: "🧊")
        case .freezer:
            return ZoneStyle(
                background: AnyView(LinearGradient(colors: [Color(red: 0.70, green: 0.86, blue: 0.98), Color(red: 0.40, green: 0.62, blue: 0.88)], startPoint: .top, endPoint: .bottom)),
                shelf: AnyView(Color.white.opacity(0.7)),
                card: Color(red: 0.92, green: 0.97, blue: 1), secondary: Color(red: 0.12, green: 0.3, blue: 0.55), emptyEmoji: "❄️")
        case .pantry:
            return ZoneStyle(
                background: AnyView(LinearGradient(colors: [Color(red: 0.45, green: 0.29, blue: 0.17), Color(red: 0.30, green: 0.19, blue: 0.11)], startPoint: .top, endPoint: .bottom)),
                shelf: AnyView(LinearGradient(colors: [Color(red: 0.78, green: 0.56, blue: 0.34), Color(red: 0.6, green: 0.41, blue: 0.24)], startPoint: .top, endPoint: .bottom)),
                card: Color(red: 0.98, green: 0.93, blue: 0.84), secondary: Color(red: 0.98, green: 0.86, blue: 0.68), emptyEmoji: "🫙")
        case .counter:
            return ZoneStyle(
                background: AnyView(LinearGradient(colors: [Color(red: 0.95, green: 0.86, blue: 0.70), Color(red: 0.84, green: 0.68, blue: 0.47)], startPoint: .top, endPoint: .bottom)),
                shelf: AnyView(Color(red: 0.6, green: 0.42, blue: 0.25)),
                card: .white, secondary: Color(red: 0.4, green: 0.26, blue: 0.14), emptyEmoji: "🍽️")
        }
    }
}

/// One food sitting on a shelf.
struct FoodChip: View {
    let item: PantryItem
    let style: ZoneStyle
    @State private var wobble = false
    private var urgent: Bool { (item.daysLeft ?? 99) <= 2 }

    var body: some View {
        VStack(spacing: 4) {
            Text(FoodIcon.of(item)).font(.system(size: 40))
                .rotationEffect(.degrees(urgent && wobble ? 6 : 0))
            Text(item.name).font(.caption.weight(.semibold)).lineLimit(2).multilineTextAlignment(.center)
                .foregroundStyle(.black.opacity(0.8))
            Text(Theme.expiryText(item.daysLeft)).font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Theme.expiryColor(item.daysLeft).opacity(0.2), in: .capsule)
                .foregroundStyle(Theme.expiryColor(item.daysLeft))
        }
        .frame(width: 96, height: 118)
        .background(style.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(urgent ? Theme.expiryColor(item.daysLeft) : .clear, lineWidth: 2))
        .shadow(color: urgent ? Theme.expiryColor(item.daysLeft).opacity(0.5) : .black.opacity(0.15), radius: urgent ? 10 : 4, y: 3)
        .onAppear {
            guard urgent else { return }
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { wobble = true }
        }
    }
}

/// Frosty corners and drifting snow inside the freezer.
struct FrostOverlay: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15)) { ctx in
            Canvas { g, size in
                let t = ctx.date.timeIntervalSinceReferenceDate
                for i in 0..<28 {
                    let seed = Double(i) * 137.5
                    let x = (sin(seed) * 0.5 + 0.5) * size.width + sin(t * 0.6 + seed) * 12
                    let y = ((t * (12 + Double(i % 5) * 4) + seed * 7).truncatingRemainder(dividingBy: size.height + 20)) - 10
                    let r = 1.5 + Double(i % 3)
                    g.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(0.7)))
                }
            }
        }
        .overlay(
            RadialGradient(colors: [.white.opacity(0.55), .clear], center: .topLeading, startRadius: 0, endRadius: 180)
        )
        .overlay(
            RadialGradient(colors: [.white.opacity(0.45), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 200)
        )
        .ignoresSafeArea()
    }
}
