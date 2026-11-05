import SwiftUI
import SwiftData

struct ChefView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<PantryItem> { !$0.isUsedUp }) private var items: [PantryItem]
    @Query private var spices: [Spice]
    @Query private var profiles: [KitchenProfile]
    @Query(sort: \SavedRecipe.createdAt, order: .reverse) private var saved: [SavedRecipe]

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
                                RecipeRow(title: (r.isFavorite ? "★ " : "") + r.title, summary: r.summary, minutes: r.minutes)
                            }
                        }
                        .onDelete { offsets in offsets.forEach { context.delete(saved[$0]) } }
                    }
                }
            }
            .navigationTitle("Chef")
        }
    }

    private func cook() async {
        guard let profile = profiles.first else { return }
        working = true; error = nil; defer { working = false }
        let req = ChefAI.RecipeRequest(mood: mood, maxMinutes: maxMinutes,
                                       mustUse: items.filter { mustUse.contains($0.id) }.map(\.name))
        do {
            let out = try await chef.suggestRecipes(items: items, spices: spices, profile: profile, request: req)
            ideas = out.recipes; blocked = out.blocked
            if ideas.isEmpty { error = "No safe ideas came back. Try again or loosen the request." }
        } catch {
            self.error = "The chef got stuck: \(error.localizedDescription)"
        }
    }
}

struct RecipeRow: View {
    let title: String, summary: String, minutes: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            Label("\(minutes) min", systemImage: "clock").font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 2)
    }
}

struct RecipeDetailView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<PantryItem> { !$0.isUsedUp }) private var items: [PantryItem]
    let title: String, summary: String, minutes: Int, servings: Int
    let ingredients: [String], steps: [String]
    var idea: RecipeIdea? = nil
    var saved: SavedRecipe? = nil
    @State private var didSave = false
    @State private var showUseUp = false

    private var usedItems: [PantryItem] {
        let names = (idea?.usesFromKitchen ?? []).map { $0.lowercased() }
        let text = (names + ingredients.map { $0.lowercased() }).joined(separator: " ")
        return items.filter { text.contains($0.name.lowercased()) }
    }

    var body: some View {
        List {
            Section {
                Text(summary)
                HStack { Label("\(minutes) min", systemImage: "clock"); Spacer(); Label("Serves \(servings)", systemImage: "person.2") }
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("Ingredients") { ForEach(ingredients, id: \.self) { Text("• \($0)") } }
            Section("Steps") {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(i + 1)").font(.headline).foregroundStyle(Theme.accent).frame(width: 22)
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
        .confirmationDialog("Mark these as used up?", isPresented: $showUseUp, titleVisibility: .visible) {
            Button("Mark \(usedItems.count) used up") { usedItems.forEach { $0.isUsedUp = true } }
        } message: { Text(usedItems.map(\.name).joined(separator: ", ")) }
    }
}
