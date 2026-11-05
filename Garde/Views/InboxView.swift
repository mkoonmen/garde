import SwiftUI
import SwiftData

/// Recipes shared to Garde from other apps. Each one is read, checked for allergens,
/// and compared with the pantry so you can see what you'd need to buy.
struct InboxView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [KitchenProfile]
    @Query(filter: #Predicate<PantryItem> { !$0.isUsedUp }) private var pantry: [PantryItem]

    @State private var items: [InboxItem] = RecipeInbox.load()
    @State private var results: [UUID: Result<RecipeImporter.Imported, Error>] = [:]
    @State private var working: Set<UUID> = []

    var body: some View {
        List {
            if items.isEmpty {
                ContentUnavailableView("Nothing shared yet", systemImage: "square.and.arrow.down",
                                       description: Text("In TikTok, Instagram, Safari or Photos, tap Share → Garde. The recipe shows up here."))
            }
            ForEach(items) { item in
                Section(item.url.flatMap { URL(string: $0)?.host } ?? (item.imageFile != nil ? "Photo" : "Shared text")) {
                    row(item)
                }
            }
        }
        .navigationTitle("Shared recipes")
        .task { await processAll() }
        .refreshable { items = RecipeInbox.load(); await processAll() }
    }

    @ViewBuilder private func row(_ item: InboxItem) -> some View {
        if working.contains(item.id) {
            HStack { ProgressView(); Text("Reading the recipe…").foregroundStyle(.secondary) }
        } else if let result = results[item.id] {
            switch result {
            case .success(let imp):
                let r = imp.recipe
                if !imp.allergens.isEmpty {
                    Label("Contains \(imp.allergens.joined(separator: ", ")), which you're allergic to.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).font(.subheadline.weight(.semibold))
                }
                NavigationLink {
                    RecipeDetailView(title: r.title, summary: r.summary, minutes: r.minutes, servings: r.servings,
                                     ingredients: r.ingredients, steps: r.steps, idea: r)
                } label: { RecipeRow(title: r.title, summary: r.summary, minutes: r.minutes) }
                if !imp.missing.isEmpty {
                    DisclosureGroup("You'd need \(imp.missing.count) thing\(imp.missing.count == 1 ? "" : "s")") {
                        ForEach(imp.missing, id: \.self) { Text($0).font(.subheadline) }
                    }
                }
                HStack {
                    Button("Save", systemImage: "bookmark") {
                        context.insert(SavedRecipe(title: r.title, summary: r.summary, minutes: r.minutes, servings: r.servings,
                                                   ingredients: r.ingredients, steps: r.steps))
                        done(item)
                    }.disabled(!imp.allergens.isEmpty)
                    Spacer()
                    if !imp.missing.isEmpty {
                        Button("Add missing to List", systemImage: "cart.badge.plus") {
                            ShoppingBrain.add(needToBuy: imp.missing.map(shortName), for: r.title, day: .now, context: context)
                        }
                    }
                }.buttonStyle(.borderless)
                Button("Dismiss", role: .destructive) { done(item) }.font(.footnote)
            case .failure(let e):
                Text(e.localizedDescription).foregroundStyle(.secondary)
                HStack {
                    Button("Try again") { Task { await process(item) } }
                    Spacer()
                    Button("Remove", role: .destructive) { done(item) }
                }.buttonStyle(.borderless)
            }
        } else {
            Button("Read this recipe") { Task { await process(item) } }
        }
    }

    /// "2 cups baby spinach, washed" → "baby spinach"
    private func shortName(_ line: String) -> String {
        var s = line.lowercased()
        s = s.replacing(/^[\d\s\/½¼¾⅓⅔.\-]+/, with: "")
        s = s.replacing(/^(cups?|tablespoons?|tbsps?|teaspoons?|tsps?|lbs?|pounds?|oz|ounces?|grams?|g|kg|cans?|cloves?|pinch|bunch(es)?|sprigs?|slices?|large|small|medium)\b\.?\s*(of\s+)?/, with: "")
        return s.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? line
    }

    private func processAll() async {
        for item in items where results[item.id] == nil { await process(item) }
    }

    private func process(_ item: InboxItem) async {
        working.insert(item.id)
        defer { working.remove(item.id) }
        do { results[item.id] = .success(try await RecipeImporter.importItem(item, profile: profiles.first, pantry: pantry)) }
        catch { results[item.id] = .failure(error) }
    }

    private func done(_ item: InboxItem) {
        RecipeInbox.remove(item.id)
        withAnimation { items.removeAll { $0.id == item.id }; results[item.id] = nil }
    }
}
