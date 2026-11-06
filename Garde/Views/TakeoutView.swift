import SwiftUI
import SwiftData

/// What you order on DoorDash / Uber Eats / Grubhub, and one tap to cook it at home.
struct TakeoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TakeoutOrder.date, order: .reverse) private var orders: [TakeoutOrder]
    @Query private var profiles: [KitchenProfile]
    @Query(filter: #Predicate<PantryItem> { !$0.isUsedUp }) private var pantry: [PantryItem]
    @State private var cooking: String?
    @State private var result: RecipeIdea?
    @State private var error: String?
    @State private var connected = GmailImporter.shared.isSignedIn

    var body: some View {
        let fav = Takeout.favorites(orders)
        List { Group {
            if orders.isEmpty {
                Section {
                    ContentUnavailableView("No takeout yet", systemImage: "bag",
                        description: Text(connected
                            ? "Garde reads DoorDash, Uber Eats, Grubhub, Seamless and Caviar receipts from your Gmail. Tap Check Gmail, or Re-read all receipts to pull in the past year."
                            : "Connect Gmail and Garde will read your DoorDash, Uber Eats and Grubhub receipts to learn what you like."))
                    NavigationLink("Gmail receipts") { GmailSettingsView() }
                }
            } else {
                Section {
                    HStack {
                        stat("\(orders.count)", "orders")
                        stat(fav.cuisines.first?.0 ?? "–", "top cuisine")
                        stat((orders.compactMap(\.total).reduce(0, +)).formatted(.currency(code: "USD").precision(.fractionLength(0))), "spent")
                    }
                }
                Section {
                    ForEach(fav.dishes.prefix(12), id: \.0) { dish, n in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(dish).font(.body.weight(.medium))
                                Text("ordered \(n)×").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if cooking == dish { ProgressView() } else {
                                Button("Cook it") { Task { await makeAtHome(dish) } }.buttonStyle(.borderedProminent).tint(Theme.copper).controlSize(.small)
                            }
                        }
                    }
                } header: { Text("Your favorite dishes") } footer: { Text("Tap Cook it for a homemade version, checked against your allergies and built around what's in your kitchen.") }
                Section("Cuisines") {
                    ForEach(fav.cuisines.prefix(6), id: \.0) { c, n in
                        Button {
                            NotificationRouter.shared.mood = "A homemade \(c) dinner as good as takeout"
                            NotificationRouter.shared.tab = 2
                            dismiss()   // back to the Chef with the mood filled in
                        } label: {
                            HStack { Text(c); Spacer(); Text("\(n) order\(n == 1 ? "" : "s")").foregroundStyle(.secondary); Image(systemName: "frying.pan").foregroundStyle(Theme.copper) }
                                .contentShape(.rect)
                        }.buttonStyle(.plain)
                    }
                }
                Section("Recent orders") {
                    ForEach(orders.prefix(25)) { o in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(o.restaurant).font(.body.weight(.semibold))
                                Spacer()
                                if let t = o.total { Text(t, format: .currency(code: "USD")).foregroundStyle(.secondary) }
                            }
                            Text("\(o.service) · \(o.date.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                            Text(o.dishes.joined(separator: " · ")).font(.caption).lineLimit(2)
                        }
                    }
                }
            }
            if let error { Section { Text(error).foregroundStyle(.orange) } }
        }.listRowBackground(RowGlass()) }
        .gardePage()
        .navigationTitle("Takeout favorites")
        .onAppear { connected = GmailImporter.shared.isSignedIn }
        .navigationDestination(item: $result) { r in
            RecipeDetailView(title: r.title, summary: r.summary, minutes: r.minutes, servings: r.servings, ingredients: r.ingredients, steps: r.steps, idea: r)
        }
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.headline).lineLimit(1).minimumScaleFactor(0.6)
            Text(l).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }

    private func makeAtHome(_ dish: String) async {
        cooking = dish; error = nil
        defer { cooking = nil }
        guard let profile = profiles.first else { error = "Set up your kitchen profile first (More → Allergies & tastes)."; return }
        if case .unavailable(let why) = ChefAI().state { error = why; return }
        let restaurant = orders.first { $0.dishes.contains { $0.caseInsensitiveCompare(dish) == .orderedSame } }?.restaurant ?? ""
        do {
            let out = try await ChefAI().suggestRecipes(items: pantry, spices: [], profile: profile,
                request: .init(mood: "A homemade, restaurant-quality version of \"\(dish)\"\(restaurant.isEmpty ? "" : " like from \(restaurant)"). Make all 3 ideas variations of this dish.",
                               maxMinutes: 75, mustUse: []))
            if let first = out.recipes.first { result = first }
            else { error = out.blocked > 0 ? "Every version of that dish used one of your allergens, so it was skipped." : "The chef couldn't write that one. Try again." }
        } catch { self.error = error.localizedDescription }
    }
}

extension RecipeIdea: Hashable, Identifiable {
    var id: String { title + "|" + summary }
    static func == (a: RecipeIdea, b: RecipeIdea) -> Bool { a.title == b.title && a.summary == b.summary && a.ingredients == b.ingredients && a.steps == b.steps }
    func hash(into h: inout Hasher) { h.combine(title); h.combine(summary) }
}
