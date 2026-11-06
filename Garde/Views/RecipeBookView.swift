import SwiftUI
import SwiftData

/// All saved recipes: search, filter by what you can make right now, quick, favorites, loved.
struct RecipeBookView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedRecipe.title) private var saved: [SavedRecipe]
    @Query(filter: #Predicate<PantryItem> { !$0.isUsedUp }) private var items: [PantryItem]
    @Query private var logs: [CookLog]
    @State private var query = ""
    @State private var filter = Filter.all
    @State private var missingByID: [UUID: Int] = [:]

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", canMake = "Can make now", quick = "30 min or less", favorites = "Favorites", loved = "Rated 4+"
        var id: String { rawValue }
    }

    private var shown: [SavedRecipe] {
        let best = Dictionary(grouping: logs) { $0.title.lowercased() }.mapValues { $0.map(\.rating).max() ?? 0 }
        return saved.filter { r in
            (query.isEmpty || r.title.localizedCaseInsensitiveContains(query) || r.ingredients.contains { $0.localizedCaseInsensitiveContains(query) })
            && {
                switch filter {
                case .all: true
                case .canMake: (missingByID[r.id] ?? 99) == 0
                case .quick: r.minutes > 0 && r.minutes <= 30
                case .favorites: r.isFavorite
                case .loved: (best[r.title.lowercased()] ?? 0) >= 4
                }
            }()
        }
    }

    private var stockSignature: String {
        let stock = items.map { "\($0.id)/\($0.ingredientName)/\($0.availableLabel)/\($0.daysLeft ?? 999)" }.sorted().joined(separator: "|")
        let recipes = saved.map { $0.id.uuidString + $0.ingredients.joined(separator: "|") }.sorted().joined(separator: "/")
        return stock + recipes
    }

    var body: some View {
        List { Group {
            Section {
                Picker("Show", selection: $filter) { ForEach(Filter.allCases) { Text($0.rawValue).tag($0) } }
            }
            if shown.isEmpty {
                ContentUnavailableView(filter == .canMake ? "Nothing ready to make" : "No recipes", systemImage: "books.vertical",
                                       description: Text(filter == .canMake ? "No saved recipe has all its recorded ingredient amounts available." : "Try another search or filter."))
            }
            ForEach(shown) { r in
                NavigationLink {
                    RecipeDetailView(title: r.title, summary: r.summary, minutes: r.minutes, servings: r.servings,
                                     ingredients: r.ingredients, steps: r.steps, saved: r)
                } label: {
                    HStack {
                        RecipeRow(title: r.title, summary: r.summary, minutes: r.minutes)
                        if let m = missingByID[r.id] {
                            Text(m == 0 ? "Ready" : "\(m) to buy or check").font(.caption2.weight(.semibold))
                                .foregroundStyle(m == 0 ? .green : .secondary)
                        }
                    }
                }
                .swipeActions(edge: .leading) {
                    Button(r.isFavorite ? "Unfavorite" : "Favorite", systemImage: r.isFavorite ? "star.slash" : "star") { r.isFavorite.toggle() }.tint(.yellow)
                }
            }
            .onDelete { offsets in let list = shown; offsets.forEach { context.delete(list[$0]) } }
        }.listRowBackground(RowGlass()) }
        .gardePage()
        .searchable(text: $query, prompt: "Search recipes or ingredients")
        .navigationTitle("Recipe book")
        .task(id: stockSignature) {
            var m: [UUID: Int] = [:]
            for r in saved { m[r.id] = RecipeScaler.missing(r.ingredients, have: items).count }
            missingByID = m
        }
    }
}
