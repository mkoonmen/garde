import SwiftUI
import SwiftData

/// Everything you've cooked: ratings, what you'd change, cost, by month. Open a dish to cook it again.
struct CookJournalView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CookLog.date, order: .reverse) private var logs: [CookLog]
    @Query private var saved: [SavedRecipe]
    @State private var query = ""

    private var months: [(String, [CookLog])] {
        let shown = query.isEmpty ? logs : logs.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.wouldChange.localizedCaseInsensitiveContains(query) }
        let g = Dictionary(grouping: shown) { $0.date.formatted(.dateTime.year().month(.wide)) }
        return g.sorted { ($0.value.first?.date ?? .distantPast) > ($1.value.first?.date ?? .distantPast) }
    }

    var body: some View {
        List { Group {
            if logs.isEmpty {
                ContentUnavailableView("Nothing cooked yet", systemImage: "book.closed",
                                       description: Text("Finish a recipe in Cook mode and rate it; it lands here."))
            } else {
                Section {
                    HStack {
                        stat("\(logs.count)", "dishes")
                        stat(String(format: "%.1f★", Double(logs.map(\.rating).reduce(0, +)) / Double(max(logs.filter { $0.rating > 0 }.count, 1))), "average")
                        stat(logs.compactMap(\.cost).reduce(0, +).formatted(.currency(code: "USD").precision(.fractionLength(0))), "cooked")
                    }
                }
            }
            ForEach(months, id: \.0) { month, list in
                Section(month) {
                    ForEach(list) { l in
                        let recipe = saved.first { $0.title.caseInsensitiveCompare(l.title) == .orderedSame }
                        NavigationLink {
                            if let r = recipe {
                                RecipeDetailView(title: r.title, summary: r.summary, minutes: r.minutes, servings: r.servings, ingredients: r.ingredients, steps: r.steps, saved: r)
                            } else {
                                ContentUnavailableView(l.title, systemImage: "book.closed", description: Text("This recipe wasn't saved."))
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(l.title).font(.body.weight(.medium))
                                    if l.neverAgain { Text("NEVER AGAIN").font(.caption2.weight(.bold)).foregroundStyle(.red) }
                                    Spacer()
                                    Text(String(repeating: "★", count: max(0, min(l.rating, 5)))).foregroundStyle(Theme.gold).font(.caption)
                                }
                                HStack {
                                    Text(l.date.formatted(.dateTime.weekday(.abbreviated).month().day()))
                                    if let c = l.cost { Text("· \(c.formatted(.currency(code: "USD")))") }
                                }.font(.caption).foregroundStyle(.secondary)
                                if !l.wouldChange.isEmpty { Text("Next time: \(l.wouldChange)").font(.caption).foregroundStyle(Theme.copper) }
                            }
                        }
                    }
                    .onDelete { offsets in offsets.forEach { context.delete(list[$0]) } }
                }
            }
        }.listRowBackground(RowGlass()) }
        .gardePage()
        .searchable(text: $query, prompt: "Search what you've cooked")
        .navigationTitle("Cooking journal")
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) { Text(v).font(.headline); Text(l).font(.caption2).foregroundStyle(.secondary) }.frame(maxWidth: .infinity)
    }
}
