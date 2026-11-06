import SwiftUI
import SwiftData

/// First-run setup, about a minute: allergies, who you cook for, what's already in the kitchen, the spice rack.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [KitchenProfile]
    var onFinish: () -> Void

    @State private var page = 0
    @State private var allergies: Set<String> = []
    @State private var customAllergy = ""
    @State private var household = 1
    @State private var skill = "Confident home cook"
    @State private var loves = ""
    @State private var dislikes = ""
    @State private var staples: Set<String> = []
    @State private var spices: Set<String> = []
    @State private var nutExceptions: Set<String> = []
    static let nutChoices = ["Almonds", "Hazelnuts", "Cashews", "Pistachios", "Walnuts", "Pecans", "Macadamias", "Pine nuts", "Brazil nuts"]

    static let commonAllergies = ["Peanuts", "Tree nuts", "Shellfish", "Fish", "Dairy", "Eggs", "Gluten", "Soy", "Sesame"]
    static let stapleChoices: [(String, FoodCategory)] = [
        ("Eggs", .eggs), ("Milk", .dairy), ("Butter", .dairy), ("Parmesan", .cheese), ("Olive oil", .condiments),
        ("Garlic", .produce), ("Onions", .produce), ("Lemons", .fruit), ("Rice", .grains), ("Pasta", .grains),
        ("Flour", .grains), ("Sugar", .grains), ("Chicken broth", .canned), ("Canned tomatoes", .canned),
        ("Soy sauce", .condiments), ("Dijon mustard", .condiments), ("Honey", .condiments), ("Bread", .bakery),
        ("Potatoes", .produce), ("Mayonnaise", .condiments),
    ]
    static let spiceChoices = ["Black pepper", "Kosher salt", "Garlic powder", "Onion powder", "Paprika", "Smoked paprika", "Cumin",
                               "Chili powder", "Cayenne", "Red pepper flakes", "Oregano", "Basil", "Thyme", "Rosemary", "Bay leaves",
                               "Italian seasoning", "Cinnamon", "Nutmeg", "Coriander", "Turmeric", "Curry powder", "Everything bagel"]

    private let pages = 5

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: Double(page), total: Double(pages - 1)).tint(Theme.accent).padding()
                .opacity(page == 0 ? 0 : 1)
            TabView(selection: $page) {
                welcome.tag(0)
                allergyPage.tag(1)
                aboutYou.tag(2)
                choicePage(title: "What's already in your kitchen?", subtitle: "Tap what you have. Garde estimates freshness; you can fix dates later.",
                           options: Self.stapleChoices.map(\.0), selection: $staples).tag(3)
                choicePage(title: "Your spice rack", subtitle: "Garde tracks levels and freshness, and the chef cooks with what you have.",
                           options: Self.spiceChoices, selection: $spices).tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.snappy, value: page)

            HStack {
                if page > 0 { Button("Back") { page -= 1 }.foregroundStyle(.secondary) }
                Spacer()
                Button(page == pages - 1 ? "Start cooking" : page == 0 ? "Set up Garde" : "Next") {
                    if page == pages - 1 { finish() } else { page += 1 }
                }
                .buttonStyle(GardeProminent()).controlSize(.large)
            }.padding()
        }
        .background { GardeBackground() }
        .sensoryFeedback(.selection, trigger: page)
    }

    private var welcome: some View {
        VStack(spacing: 20) {
            Spacer()
            Image("LaunchLogo").resizable().scaledToFit().frame(width: 180, height: 180).clipShape(.rect(cornerRadius: 40))
                .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
            Text("Garde").font(.system(size: 44, weight: .bold, design: .serif))
            Text("Your kitchen, kept. Garde tracks what you have, tells you what to use first, and cooks with you, all on this iPhone.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 32)
            Spacer()
        }
    }

    private var allergyPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header("Any food allergies?", "Garde will never suggest a recipe with these, and warns you when you scan one.")
                FlowChips(options: Self.commonAllergies + allergies.filter { !Self.commonAllergies.contains($0) }.sorted(), selection: $allergies)
                if allergies.contains("Tree nuts") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Any tree nuts you CAN eat?").font(.subheadline.weight(.semibold))
                        FlowChips(options: Self.nutChoices, selection: $nutExceptions)
                        Text(nutExceptions.isEmpty ? "Leave empty if all tree nuts are off limits." : "Everything else stays blocked, including unnamed \"nuts\".")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(12).background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
                }
                HStack {
                    TextField("Something else", text: $customAllergy).textFieldStyle(.roundedBorder).submitLabel(.done).onSubmit(addCustom)
                    Button("Add", action: addCustom).disabled(customAllergy.isEmpty)
                }
                Text(allergies.isEmpty ? "No allergies? Just tap Next." : "You can change these anytime in More → Allergies & tastes.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding()
        }
    }

    private var aboutYou: some View {
        Form { Group {
            Section { header("A little about how you cook", nil) }.listRowBackground(Color.clear)
            Section {
                Stepper("Cooking for \(household)", value: $household, in: 1...12)
                Picker("Skill", selection: $skill) {
                    ForEach(["Beginner", "Confident home cook", "Advanced / restaurant level"], id: \.self) { Text($0) }
                }
            }
            Section("Foods you love (optional)") { TextField("e.g. steak, seafood, Italian, spicy", text: $loves, axis: .vertical) }
            Section("Foods to avoid (optional)") { TextField("e.g. blue cheese, cilantro", text: $dislikes, axis: .vertical) }
        }.listRowBackground(RowGlass()) }
        .scrollContentBackground(.hidden)
    }

    private func choicePage(title: String, subtitle: String, options: [String], selection: Binding<Set<String>>) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(title, subtitle)
                FlowChips(options: options, selection: selection)
                Button(selection.wrappedValue.count == options.count ? "Clear all" : "Select all") {
                    selection.wrappedValue = selection.wrappedValue.count == options.count ? [] : Set(options)
                }.font(.footnote)
            }.padding()
        }
    }

    private func header(_ title: String, _ subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title.weight(.bold)).fontDesign(.serif)
            if let subtitle { Text(subtitle).foregroundStyle(.secondary) }
        }
    }

    private func addCustom() {
        let t = customAllergy.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { allergies.insert(t.prefix(1).uppercased() + t.dropFirst()) }
        customAllergy = ""
    }

    private func finish() {
        let profile = profiles.first ?? { let p = KitchenProfile(); context.insert(p); return p }()
        var chosen = allergies
        if chosen.contains("Tree nuts"), !nutExceptions.isEmpty {
            // One entry with the exceptions; a plain "Tree nuts" next to it would still block them.
            chosen.remove("Tree nuts")
            chosen.insert("Tree nuts except " + Self.nutChoices.filter(nutExceptions.contains).map { $0.lowercased() }.joined(separator: ", "))
            profile.allergies.removeAll { $0.caseInsensitiveCompare("Tree nuts") == .orderedSame }
        }
        profile.allergies = Array(Set(profile.allergies).union(chosen)).sorted()
        Task { await Notifier.requestPermission() }   // "Garde would like to send notifications" now makes sense: expiry reminders
        profile.householdSize = household
        profile.skillLevel = skill
        let split = { (s: String) in s.split(whereSeparator: { $0 == "," || $0 == "\n" }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        profile.loves = Array(Set(profile.loves + split(loves))).sorted()
        profile.dislikes = Array(Set(profile.dislikes + split(dislikes))).sorted()

        for (name, cat) in Self.stapleChoices where staples.contains(name) {
            let loc = ShelfLife.defaultLocation(for: cat, name: name)
            context.insert(PantryItem(name: name, category: cat, location: loc,
                                      expirationDate: ShelfLife.estimatedExpiration(name: name, category: cat, in: loc), expirationIsEstimated: true))
        }
        for name in Self.spiceChoices where spices.contains(name) {
            context.insert(Spice(name: name, isWholeSpice: name == "Bay leaves"))
        }
        try? context.save()
        onFinish()
    }
}

/// Wrapping row of tappable chips.
struct FlowChips: View {
    let options: [String]
    @Binding var selection: Set<String>
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(options, id: \.self) { o in
                let on = selection.contains(o)
                Button {
                    if on { selection.remove(o) } else { selection.insert(o) }
                } label: {
                    HStack(spacing: 4) {
                        if on { Image(systemName: "checkmark") }
                        Text(o)
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .foregroundStyle(on ? Theme.cream : .primary)
                    .background(on ? AnyShapeStyle(Theme.navy) : AnyShapeStyle(Theme.card), in: .capsule)
                    .overlay(Capsule().strokeBorder(Theme.accent.opacity(on ? 0 : 0.2)))
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: on)
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing; rowH = max(rowH, size.height)
        }
        return CGSize(width: width, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; rowH = max(rowH, size.height)
        }
    }
}
