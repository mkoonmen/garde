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
    @State private var noShopping = false
    @State private var mustUse: Set<UUID> = []
    @State private var ideas: [RecipeIdea] = []
    @State private var blocked = 0
    @State private var working = false
    @State private var error: String?

    private let moods = ["Quick weeknight", "Comfort food", "Date night", "High protein", "Light & fresh", "Impress guests"]
    private var expiring: [PantryItem] { items.filter { ($0.daysLeft ?? 99) <= 3 }.sorted { ($0.daysLeft ?? 0) < ($1.daysLeft ?? 0) } }

    var body: some View {
        NavigationStack {
            List { Group {
                if case .unavailable(let why) = chef.state {
                    Section { Label(why, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                }

                Section {
                    NavigationLink { ChefChatView() } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "bubble.left.and.text.bubble.right.fill").font(.title2).foregroundStyle(Theme.cream)
                                .frame(width: 48, height: 48).background(Theme.navy.gradient, in: .rect(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Ask the chef").gardeHeading(.headline)
                                Text("Type or talk. Works with no internet.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                let shared = RecipeInbox.load().count
                Section {
                    NavigationLink { InboxView() } label: {
                        Label(shared == 0 ? "Recipes shared from other apps" : "\(shared) shared recipe\(shared == 1 ? "" : "s") waiting",
                              systemImage: "square.and.arrow.down")
                    }
                    NavigationLink { FridgeCheckView() } label: { Label("Fridge check-in", systemImage: "camera.viewfinder") }
                    NavigationLink { TakeoutView() } label: { Label("Takeout favorites", systemImage: "bag") }
                    NavigationLink { HostView() } label: { Label("Host a dinner", systemImage: "party.popper") }
                } footer: { Text("Share a TikTok, Instagram post, web page or photo to Garde to save the recipe.") }

                let again = cookAgain
                if !again.isEmpty {
                    Section {
                        ForEach(again) { r in
                            NavigationLink { RecipeDetailView(title: r.title, summary: r.summary, minutes: r.minutes, servings: r.servings,
                                                              ingredients: r.ingredients, steps: r.steps, saved: r) } label: {
                                RecipeRow(title: r.title, summary: r.summary, minutes: r.minutes)
                            }
                        }
                    } header: { Text("Cook again") } footer: { Text("Dishes you loved and haven't made in a while.") }
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Seasonal.now(), id: \.self) { p in
                                Button(p.capitalized) { mood = "Something that celebrates \(p), in season now" }
                                    .buttonStyle(.bordered).tint(.green)
                            }
                        }
                    }
                } header: { Text("In season now") }

                Section("Or pick a mood") {
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
                    Toggle("Only what I have (no shopping)", isOn: $noShopping)
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
                        HStack { Spacer(); if working { ProgressView().tint(.white) } else { Label("Cook something", systemImage: "sparkles").symbolEffect(.pulse, isActive: working) }; Spacer() }
                            .font(.headline).foregroundStyle(.white).padding(.vertical, 14)
                            .background(LinearGradient(colors: [Theme.copper, Color(red: 0.55, green: 0.22, blue: 0.35), Theme.navy], startPoint: .leading, endPoint: .trailing),
                                        in: .rect(cornerRadius: 18))
                            .shadow(color: Theme.copper.opacity(0.5), radius: 16, y: 6)
                    }
                    .buttonStyle(.plain).listRowBackground(Color.clear).listRowInsets(EdgeInsets()).disabled(working || chef.state != .available)
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
            }.listRowBackground(RowGlass()) }
            .gardePage()
            .navigationTitle("Chef")
            .onAppear(perform: takeRoutedItem)
            .onChange(of: NotificationRouter.shared.mustUse) { _, _ in takeRoutedItem() }
            .toolbar {
                NavigationLink { MealPlanView() } label: { Label("Week plan", systemImage: "calendar") }
            }
        }
    }

    /// An expiration reminder was tapped: tick that item as "must use" and set the mood.
    private func takeRoutedItem() {
        guard let name = NotificationRouter.shared.mustUse else { return }
        NotificationRouter.shared.mustUse = nil
        if let item = items.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            mustUse.insert(item.id)
            if mood.isEmpty { mood = "Use up the \(item.name) before it goes bad" }
        }
    }

    /// Saved recipes rated 4+ that haven't been cooked in three weeks (never "never again").
    private var cookAgain: [SavedRecipe] {
        let cutoff = Date.now.addingTimeInterval(-21 * 86_400)
        let latest = Dictionary(grouping: logs) { $0.title.lowercased() }
        return saved.filter { r in
            guard let l = latest[r.title.lowercased()], !l.contains(where: \.neverAgain) else { return false }
            let best = l.map(\.rating).max() ?? 0
            let last = l.map(\.date).max() ?? .distantPast
            return best >= 4 && last < cutoff
        }.prefix(4).map { $0 }
    }

    private func cook() async {
        guard let profile = profiles.first else { return }
        working = true; error = nil; defer { working = false }
        let req = ChefAI.RecipeRequest(mood: mood, maxMinutes: maxMinutes,
                                       mustUse: items.filter { mustUse.contains($0.id) }.map(\.name), noShopping: noShopping)
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
    @Query private var profiles: [KitchenProfile]
    @State private var people = 0
    @State private var swaps: [Int: Swaps] = [:]
    @State private var swapping: Int?
    @State private var swapError: String?
    @State private var addedMissing = false
    @State private var plating: Plating?
    @State private var platingLoading = false

    private var serves: Int { people == 0 ? servings : people }
    private var factor: Double { servings > 0 ? Double(serves) / Double(servings) : 1 }
    private var shownIngredients: [String] { ingredients.map { RecipeScaler.scale($0, by: factor) } }

    /// Ingredient lines with nothing matching in the kitchen (salt, pepper, oil and water assumed).
    private var missing: [String] {
        let basics = ["salt", "pepper", "water", "olive oil", "oil", "ice"]
        return shownIngredients.filter { line in
            let food = RecipeScaler.foodName(line).lowercased()
            guard !food.isEmpty, !basics.contains(where: { food == $0 || food.hasPrefix($0 + " and") }) else { return false }
            return !items.contains { ShoppingBrain.appears($0.name, in: line) || ShoppingBrain.appears(food, in: $0.name) }
        }
    }

    private var cost: (total: Double, matched: Int) { CostCalculator.estimate(ingredients: shownIngredients, items: allItems) }
    private var nutrition: Nutrition.Totals { Nutrition.estimate(ingredients: ingredients).perServing(servings) }

    private var usedItems: [PantryItem] {
        let text = ((idea?.usesFromKitchen ?? []) + ingredients).joined(separator: " ")
        return items.filter { !$0.isLeftover && ShoppingBrain.appears($0.name, in: text) }
    }

    var body: some View {
        List { Group {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: Theme.dishSymbol(title)).font(.largeTitle).foregroundStyle(Theme.cream)
                        .frame(width: 72, height: 72).background(Theme.navy.gradient, in: .rect(cornerRadius: 18))
                    Text(title).font(.title2.weight(.bold)).fontDesign(.serif)
                }
                Text(summary)
                HStack {
                    Label("\(minutes) min", systemImage: "clock")
                    Spacer()
                    Stepper(value: Binding(get: { serves }, set: { people = $0 }), in: 1...20) {
                        Label("Serves \(serves)", systemImage: "person.2")
                    }.fixedSize()
                }
                .font(.subheadline).foregroundStyle(.secondary)
                if nutrition.isReliable {
                    HStack(spacing: 0) {
                        NutrientTile(value: "\(Int(nutrition.kcal.rounded()))", label: "kcal")
                        NutrientTile(value: "\(Int(nutrition.protein.rounded()))g", label: "protein")
                        NutrientTile(value: "\(Int(nutrition.carbs.rounded()))g", label: "carbs")
                        NutrientTile(value: "\(Int(nutrition.fat.rounded()))g", label: "fat")
                    }
                    Text("Per serving, estimated offline from \(nutrition.counted) of \(nutrition.total) ingredients.").font(.caption2).foregroundStyle(.tertiary)
                }
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
            Section {
                ForEach(Array(shownIngredients.enumerated()), id: \.offset) { i, line in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("• \(line)")
                            Spacer()
                            if swapping == i { ProgressView().controlSize(.small) }
                            else {
                                Button { Task { await swap(i, line) } } label: { Image(systemName: "arrow.left.arrow.right.circle") }
                                    .buttonStyle(.borderless).foregroundStyle(Theme.accent).accessibilityLabel("Substitute")
                            }
                        }
                        if let s = swaps[i] {
                            ForEach(s.options, id: \.self) { Text("↳ \($0)").font(.subheadline).foregroundStyle(Theme.copper) }
                            if !s.note.isEmpty { Text(s.note).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                if let swapError { Text(swapError).font(.caption).foregroundStyle(.orange) }
                let need = missing
                if !need.isEmpty {
                    Button(addedMissing ? "Added to your list" : "Add \(need.count) missing to list", systemImage: addedMissing ? "checkmark" : "cart.badge.plus") {
                        ShoppingBrain.add(needToBuy: need.map { RecipeScaler.foodName($0) }, for: title, day: .now, context: context)
                        addedMissing = true
                    }.disabled(addedMissing)
                }
            } header: { Text("Ingredients") } footer: {
                Text(factor == 1 ? "Tap ⇄ next to an ingredient for a substitute." : "Amounts scaled from \(servings) to \(serves) servings.")
            }
            Section("Plate it like a restaurant") {
                if let plating {
                    ForEach(Array(plating.steps.enumerated()), id: \.offset) { i, s in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "\(i + 1).circle").foregroundStyle(Theme.copper)
                            Text(s)
                        }
                    }
                    if !plating.garnish.isEmpty { Label(plating.garnish, systemImage: "leaf").font(.subheadline).foregroundStyle(.secondary) }
                } else {
                    Button(platingLoading ? "Thinking…" : "Show me how to plate it", systemImage: "fork.knife") {
                        guard let profile = profiles.first else { return }
                        platingLoading = true
                        Task { plating = try? await chef.plating(dish: title, ingredients: ingredients, profile: profile); platingLoading = false }
                    }.disabled(platingLoading)
                }
            }
            if let saved {
                Section("My notes") {
                    TextField("Your tweaks: \"less salt, add chili flakes\"", text: Binding(get: { saved.notes }, set: { saved.notes = $0 }), axis: .vertical)
                }
            }
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
        }.listRowBackground(RowGlass()) }
        .gardePage()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ShareLink(item: "\(title)\n\(summary)\n\nServes \(serves) · \(minutes) min\n\nINGREDIENTS\n" + shownIngredients.map { "• " + $0 }.joined(separator: "\n")
                      + "\n\nSTEPS\n" + steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n") + "\n\nFrom Garde") {
                Label("Share recipe", systemImage: "square.and.arrow.up")
            }
        }
        .fullScreenCover(isPresented: $cooking) {
            CookModeView(title: title, steps: steps, ingredients: shownIngredients, servings: serves, usedItems: usedItems,
                         estimatedCost: cost.matched > 0 ? cost.total : nil) { saved?.timesCooked += 1 }
        }
        .confirmationDialog("Mark these as used up?", isPresented: $showUseUp, titleVisibility: .visible) {
            Button("Mark \(usedItems.count) used up") { usedItems.forEach { $0.markUsed() } }
        } message: { Text(usedItems.map(\.name).joined(separator: ", ")) }
    }
}

extension RecipeDetailView {
    fileprivate func swap(_ i: Int, _ line: String) async {
        if swaps[i] != nil { swaps[i] = nil; return }
        guard let profile = profiles.first else { return }
        swapping = i; swapError = nil
        defer { swapping = nil }
        do {
            if let s = try await chef.substitute(line, dish: title, items: items, profile: profile) { swaps[i] = s }
            else { swapError = "No safe substitute for that one." }
        } catch { swapError = "The chef couldn't think of a swap. Try again." }
    }
}

struct NutrientTile: View {
    let value: String, label: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).fontDesign(.serif).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
}
