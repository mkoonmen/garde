import SwiftUI
import SwiftData

/// Having people over: a make-ahead menu, a prep timeline, and the shopping list, safe for you and your guests.
struct HostView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<PantryItem> { !$0.isUsedUp }) private var items: [PantryItem]
    @Query private var profiles: [KitchenProfile]
    @Query private var logs: [CookLog]
    @State private var guests = 6
    @State private var occasion = ""
    @State private var guestAllergies = ""
    @State private var menu: HostMenu?
    @State private var working = false
    @State private var message: String?
    @State private var added = false
    @State private var turkeyLb = 14.0
    @State private var dinnerDay = HostView.nextThanksgiving()

    private let occasions = ["Thanksgiving", "Friendsgiving", "Christmas dinner", "Game day", "Date night", "Birthday dinner", "Holiday cocktail party"]

    /// 4th Thursday of November (this year, or next if it has passed).
    static func nextThanksgiving(from now: Date = .now) -> Date {
        let cal = Calendar.current
        for year in [cal.component(.year, from: now), cal.component(.year, from: now) + 1] {
            var c = DateComponents(); c.year = year; c.month = 11; c.weekday = 5; c.weekdayOrdinal = 4; c.hour = 16
            if let d = cal.date(from: c), d > now { return d }
        }
        return now
    }

    static func nextChristmas(from now: Date = .now) -> Date {
        let cal = Calendar.current
        let y = cal.component(.year, from: now)
        let d = cal.date(from: DateComponents(year: y, month: 12, day: 25, hour: 16)) ?? now
        return d > now ? d : cal.date(from: DateComponents(year: y + 1, month: 12, day: 25, hour: 16)) ?? now
    }

    /// Fridge thawing: about 1 day per 4–5 lb (USDA). Returns when it must go in the fridge.
    static func thawStart(pounds: Double, serving: Date) -> Date {
        let days = Int((pounds / 4.5).rounded(.up))
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: serving)) ?? serving
    }

    var body: some View {
        List { Group {
            Section {
                Stepper("\(guests) people", value: $guests, in: 2...40)
                TextField("Occasion: \"Friendsgiving\", \"birthday dinner\"", text: $occasion)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack { ForEach(occasions, id: \.self) { o in Button(o) { occasion = o }.buttonStyle(.bordered).tint(occasion == o ? Theme.copper : .secondary) } }
                }
                TextField("Guests' allergies, comma separated", text: $guestAllergies)
            } footer: { Text("Your own allergies are always included.") }
            if occasion.localizedCaseInsensitiveContains("giving") || occasion.localizedCaseInsensitiveContains("christmas") {
                Section {
                    Stepper("Frozen turkey: \(turkeyLb.formatted()) lb", value: $turkeyLb, in: 8...30, step: 1)
                    DatePicker("Dinner", selection: $dinnerDay, displayedComponents: .date)
                    let start = Self.thawStart(pounds: turkeyLb, serving: dinnerDay)
                    Label("Move it to the fridge by **\(start.formatted(.dateTime.weekday(.wide).month().day()))**", systemImage: "snowflake")
                    Text("About \(Int((turkeyLb / 4.5).rounded(.up))) days in the fridge. Roast roughly \(Int(turkeyLb * 13 / 60))–\(Int((turkeyLb * 15 / 60).rounded(.up))) hours at 325°F unstuffed, to 165°F in the thickest part of the thigh.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("Turkey thaw") }
            }
            Section {
                Button { Task { await plan() } } label: {
                    HStack { Spacer(); if working { ProgressView() } else { Label("Plan the menu", systemImage: "party.popper") }; Spacer() }
                }.disabled(working)
            }
            if let message { Section { Text(message).foregroundStyle(.orange) } }
            if let menu {
                Section("Menu") {
                    ForEach(Array(menu.courses.enumerated()), id: \.offset) { _, c in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.course.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(Theme.copper)
                            Text(c.dish).gardeHeading(.headline)
                            Text(c.note).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Timeline") {
                    ForEach(Array(menu.timeline.enumerated()), id: \.offset) { i, t in
                        HStack(alignment: .top) { Text("\(i + 1)").foregroundStyle(Theme.accent).frame(width: 20); Text(t) }
                    }
                }
                Section("To buy") {
                    ForEach(menu.shoppingList, id: \.self) { Text("• \($0)") }
                    Button(added ? "Added to your list" : "Add all to shopping list", systemImage: added ? "checkmark" : "cart.badge.plus") {
                        ShoppingBrain.add(needToBuy: menu.shoppingList.map { RecipeScaler.foodName($0).capitalized }, for: occasion.ifEmpty("the party"), day: .now, context: context)
                        added = true
                    }.disabled(added || menu.shoppingList.isEmpty)
                }
            }
        }.listRowBackground(RowGlass()) }
        .gardePage()
        .navigationTitle("Host a dinner")
        .onChange(of: occasion) { old, o in
            // Only when the holiday first appears, so a date you picked isn't reset on every keystroke.
            let xmas = { (s: String) in s.localizedCaseInsensitiveContains("christmas") }
            let giving = { (s: String) in s.localizedCaseInsensitiveContains("giving") }
            if xmas(o) && !xmas(old) {
                let day = Self.nextChristmas()
                dinnerDay = o.localizedCaseInsensitiveContains("eve") ? Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day : day
            } else if giving(o) && !giving(old) { dinnerDay = Self.nextThanksgiving() }
        }
    }

    private func plan() async {
        guard let profile = profiles.first else { message = "Set up your kitchen profile first."; return }
        let chef = ChefAI()
        if case .unavailable(let why) = chef.state { message = why; return }
        working = true; message = nil; added = false
        defer { working = false }
        let extra = guestAllergies.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for _ in 0..<2 {   // one retry if the first menu trips an allergen
            do {
                let out = try await chef.hostMenu(guests: guests, occasion: occasion, guestAllergies: extra, items: items, profile: profile, logs: logs)
                if let m = out.menu { withAnimation { menu = m }; return }
            } catch { message = "The chef got stuck: \(error.localizedDescription)"; return }
        }
        message = "Every menu the chef wrote included an allergen, so it was thrown out. Try again or change the occasion."
    }
}
