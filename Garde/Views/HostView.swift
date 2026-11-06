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

    var body: some View {
        List { Group {
            Section {
                Stepper("\(guests) people", value: $guests, in: 2...40)
                TextField("Occasion: \"Friendsgiving\", \"birthday dinner\"", text: $occasion)
                TextField("Guests' allergies, comma separated", text: $guestAllergies)
            } footer: { Text("Your own allergies are always included.") }
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
                        ShoppingBrain.add(needToBuy: menu.shoppingList, for: occasion.ifEmpty("the party"), day: .now, context: context)
                        added = true
                    }.disabled(added || menu.shoppingList.isEmpty)
                }
            }
        }.listRowBackground(RowGlass()) }
        .gardePage()
        .navigationTitle("Host a dinner")
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
