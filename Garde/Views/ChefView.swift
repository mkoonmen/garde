import SwiftUI
import SwiftData

struct ChefView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<PantryItem> { !$0.isUsedUp }) private var items: [PantryItem]
    @Query private var spices: [Spice]
    @Query private var profiles: [KitchenProfile]
    @Query(sort: \SavedRecipe.createdAt, order: .reverse) private var saved: [SavedRecipe]
    @Query private var logs: [CookLog]

    @State private var chef = ChefAI()
    @State private var mood = ""
    @State private var maxMinutes = 45
    @State private var mustUse: Set<UUID> = []
    @State private var ideas: [RecipeIdea] = []
    @State private var blocked = 0
    @State private var working = false
    @State private var error: String?

    private let moods = ["Quick weeknight", "Comfort food", "Date night", "High protein", "Light & fresh", "Impress guests"]
    private var expiring: [PantryItem] { items.filter { ($0.daysLeft ?? 99) <= 3 }.sorted { ($0.daysLeft ?? 0) < ($1.daysLeft ?? 0) } }

    var body: some View {
        NavigationStack {
            List {
                if case .unavailable(let why) = chef.state {
                    Section { Label(why, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                }

                Section("What are you feeling?") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(moods, id: \.self) { m in
                                Button(m) { mood = mood == m ? "" : m }
                                    .buttonStyle(.bordered).tint(mood == m ? Theme.accent : .secondary)
                            }
                        }
                    }
                    TextField("Or describe it: \"something Italian with the chicken\"", text: $mood, axis: .vertical)
                    Stepper("Up to \(maxMinutes) minutes", value: $maxMinutes, in: 10...180, step: 5)
                }

                let leftovers = items.filter(\.isLeftover)
                if !leftovers.isEmpty {
                    Section {
                        Button("Remix my leftovers", systemImage: "arrow.triangle.2.circlepath") {
                            mustUse = Set(leftovers.map(\.id)); mood = "Turn the leftovers into something new"
                            Task { await cook() }
                        }
                    } footer: { Text(leftovers.map(\.name).joined(separator: ", ")) }
                }

                if !expiring.isEmpty {
                    Section {
                        ForEach(expiring) { item in
                            Button {
                                if mustUse.contains(item.id) { mustUse.remove(item.id) } else { mustUse.insert(item.id) }
                            } label: {
                                HStack {
                                    Image(systemName: mustUse.contains(item.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(Theme.accent)
                                    Text(item.name)
                                    Spacer()
                                    Text(Theme.expiryText(item.daysLeft)).font(.caption).foregroundStyle(Theme.expiryColor(item.daysLeft))
                                }
                            }.buttonStyle(.plain)
                        }
                    } header: { Text("Must use") } footer: { Text("Expiring soon. Tap to force these into the recipes.") }
                }

                Section {
                    Button { Task { await cook() } } label: {
                        HStack { Spacer(); if working { ProgressView() } else { Label("Cook something", systemImage: "sparkles") }; Spacer() }
                            .font(.headline).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent).listRowInsets(EdgeInsets()).disabled(working || chef.state != .available)
                }

                if let error { Section { Text(error).foregroundStyle(.red) } }
                if blocked > 0 {
                    Section { Label("\(blocked) idea\(blocked == 1 ? " was" : "s were") thrown out for containing an allergen.", systemImage: "shield.checkered").font(.footnote) }
                }

                if !ideas.isEmpty {
                    Section("Ideas") {
                        ForEach(Array(ideas.enumerated()), id: \.offset) { _, idea in
                            NavigationLink { RecipeDetailView(title: idea.title, summary: idea.summary, minutes: idea.minutes, servings: idea.servings,
                                                              ingredients: idea.ingredients, steps: idea.steps, idea: idea) } label: {
                                RecipeRow(title: idea.title, summary: idea.summary, minutes: idea.minutes)
                            }
                        }
                    }
                }

                if !saved.isEmpty {
                    Section("Saved recipes") {
                        ForEach(saved) { r in
                            NavigationLink { RecipeDetailView(title: r.title, summary: r.summary, minutes: r.minutes, servings: r.servings,
                                                              ingredients: r.ingredients, steps: r.steps, saved: r) } label: {
                                RecipeRow(title: r.title, summary: r.summary, minutes: r.minutes)
                            }
                        }
                        .onDelete { offsets in offsets.forEach { context.delete(saved[$0]) } }
                    }
                }
            }
            .navigationTitle("Chef")
            .toolbar {
                NavigationLink { MealPlanView() } label: { Label("Week plan", systemImage: "calendar") }
            }
        }
    }

    private func cook() async {
        guard let profile = profiles.first else { return }
        working = true; error = nil; defer { working = false }
        let req = ChefAI.RecipeRequest(mood: mood, maxMinutes: maxMinutes,
                                       mustUse: items.filter { mustUse.contains($0.id) }.map(\.name))
        do {
            let out = try await chef.suggestRecipes(items: items, spices: spices, profile: profile, logs: logs, request: req)
            withAnimation(.spring(duration: 0.45)) { ideas = out.recipes }
            blocked = out.blocked
            if ideas.isEmpty { error = "No safe ideas came back. Try again or loosen the request." }
        } catch {
            self.error = "The chef got stuck: \(error.localizedDescription)"
        }
    }
}

struct RecipeRow: View {
    let title: String, summary: String, minutes: Int
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: Theme.dishSymbol(title))
                .font(.title2).foregroundStyle(Theme.cream)
                .frame(width: 48, height: 48)
                .background(Theme.navy.gradient, in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).gardeHeading(.headline)
                Text(summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                Label("\(minutes) min", systemImage: "clock").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4)
    }
}

struct RecipeDetailView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<PantryItem> { !$0.isUsedUp }) private var items: [PantryItem]
    @Query private var allItems: [PantryItem]
    @Query private var bottles: [BarBottle]
    let title: String, summary: String, minutes: Int, servings: Int
    let ingredients: [String], steps: [String]
    var idea: RecipeIdea? = nil
    var saved: SavedRecipe? = nil
    @State private var didSave = false
    @State private var showUseUp = false
    @State private var cooking = false
    @State private var pairing: Pairing?
    @State private var pairingLoading = false
    @State private var chef = ChefAI()

    private var cost: (total: Double, matched: Int) { CostCalculator.estimate(ingredients: ingredients, items: allItems) }

    private var usedItems: [PantryItem] {
        let names = (idea?.usesFromKitchen ?? []).map { $0.lowercased() }
        let text = (names + ingredients.map { $0.lowercased() }).joined(separator: " ")
        return items.filter { text.contains($0.name.lowercased()) }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: Theme.dishSymbol(title)).font(.largeTitle).foregroundStyle(Theme.cream)
                        .frame(width: 72, height: 72).background(Theme.navy.gradient, in: .rect(cornerRadius: 18))
                    Text(title).font(.title2.weight(.bold)).fontDesign(.serif)
                }
                Text(summary)
                HStack { Label("\(minutes) min", systemImage: "clock"); Spacer(); Label("Serves \(servings)", systemImage: "person.2") }
                    .font(.subheadline).foregroundStyle(.secondary)
                if cost.matched > 0 {
                    Label("About \(cost.total.formatted(.currency(code: "USD"))) from what you paid (\(cost.matched) of \(ingredients.count) ingredients priced)",
                          systemImage: "dollarsign.circle").font(.caption).foregroundStyle(.secondary)
                }
                Button { cooking = true } label: {
                    Label("Start cook mode", systemImage: "play.circle.fill").frame(maxWidth: .infinity).font(.headline)
                }.buttonStyle(.borderedProminent).controlSize(.large)
            }
            Section("Pairing") {
                if let p = pairing {
                    if !p.bottleFromCellar.isEmpty { Label(p.bottleFromCellar, systemImage: "wineglass").font(.headline) }
                    Text(p.why).font(.subheadline)
                    if p.bottleFromCellar.isEmpty || !p.ifBuying.isEmpty { Text("If buying: \(p.ifBuying)").font(.caption).foregroundStyle(.secondary) }
                } else {
                    Button(pairingLoading ? "Thinking…" : (bottles.isEmpty ? "Suggest a drink" : "Pair from my bar"), systemImage: "wineglass") {
                        pairingLoading = true
                        Task { pairing = try? await chef.pair(dish: title, ingredients: ingredients, bottles: bottles); pairingLoading = false }
                    }.disabled(pairingLoading)
                }
            }
            Section("Ingredients") { ForEach(ingredients, id: \.self) { Text("• \($0)") } }
            Section("Steps") {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(i + 1)").font(.headline).fontDesign(.serif).foregroundStyle(Theme.accent).frame(width: 22)
                        Text(s)
                    }
                }
            }
            Section {
                if saved == nil {
                    Button(didSave ? "Saved" : "Save recipe", systemImage: didSave ? "checkmark" : "bookmark") {
                        context.insert(SavedRecipe(title: title, summary: summary, minutes: minutes, servings: servings, ingredients: ingredients, steps: steps))
                        didSave = true
                    }.disabled(didSave)
                } else if let saved {
                    Button(saved.isFavorite ? "Unfavorite" : "Favorite", systemImage: saved.isFavorite ? "star.slash" : "star") { saved.isFavorite.toggle() }
                }
                if !usedItems.isEmpty {
                    Button("I made this: mark ingredients used", systemImage: "checkmark.circle") { showUseUp = true }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $cooking) {
            CookModeView(title: title, steps: steps, ingredients: ingredients, servings: servings, usedItems: usedItems,
                         estimatedCost: cost.matched > 0 ? cost.total : nil) { saved?.timesCooked += 1 }
        }
        .confirmationDialog("Mark these as used up?", isPresented: $showUseUp, titleVisibility: .visible) {
            Button("Mark \(usedItems.count) used up") { usedItems.forEach { $0.markUsed() } }
        } message: { Text(usedItems.map(\.name).joined(separator: ", ")) }
    }
}
