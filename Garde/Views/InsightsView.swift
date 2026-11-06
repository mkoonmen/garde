import SwiftUI
import SwiftData
import Charts

/// Where the money goes: cost per meal, waste, and what you keep throwing out.
struct InsightsView: View {
    @Query private var items: [PantryItem]
    @Query(sort: \CookLog.date, order: .reverse) private var logs: [CookLog]
    @Query private var receipts: [Receipt]
    @State private var range = 30

    private var since: Date { Calendar.current.date(byAdding: .day, value: -range, to: .now)! }
    private var waste: CostCalculator.WasteReport { CostCalculator.waste(items: items, since: since) }
    private var spent: Double { receipts.filter { $0.date >= since }.compactMap(\.total).reduce(0, +) }
    private var costedMeals: [CookLog] { logs.filter { $0.date >= since && ($0.cost ?? 0) > 0 } }
    private var weeklySpend: [(Date, Double)] {
        let cal = Calendar.current
        let g = Dictionary(grouping: receipts.filter { $0.date >= since }) { cal.dateInterval(of: .weekOfYear, for: $0.date)?.start ?? $0.date }
        return g.map { ($0.key, $0.value.compactMap(\.total).reduce(0, +)) }.sorted { $0.0 < $1.0 }
    }

    var body: some View {
        List { Group {
            Picker("Range", selection: $range) {
                Text("30 days").tag(30); Text("90 days").tag(90); Text("Year").tag(365)
            }.pickerStyle(.segmented).listRowBackground(Color.clear)

            Section("Spending") {
                LabeledContent("Groceries", value: spent, format: .currency(code: "USD"))
                if weeklySpend.count > 1 {
                    Chart(weeklySpend, id: \.0) { BarMark(x: .value("Week", $0.0, unit: .weekOfYear), y: .value("Spent", $0.1)).foregroundStyle(Theme.accent) }
                        .frame(height: 140)
                }
            }

            Section {
                LabeledContent("Thrown out", value: "\(waste.tossedCount) items")
                LabeledContent("Value wasted", value: waste.tossedValue, format: .currency(code: "USD"))
                LabeledContent("Waste rate", value: waste.wasteRate, format: .percent.precision(.fractionLength(0)))
                if !waste.topTossed.isEmpty {
                    ForEach(waste.topTossed, id: \.0) { name, n in
                        HStack { Text(name); Spacer(); Text("tossed \(n)×").foregroundStyle(.secondary) }.font(.subheadline)
                    }
                }
            } header: { Text("Waste") } footer: {
                Text(waste.topTossed.first.map { "You keep tossing \($0.0.lowercased()). Buy less of it, or freeze it sooner." } ?? "Swipe items as \"Tossed\" when you throw them out so this stays accurate.")
            }

            Section("Cost per meal") {
                if costedMeals.isEmpty { Text("Finish a recipe in cook mode to see what it cost.").foregroundStyle(.secondary) }
                else {
                    LabeledContent("Average dinner", value: costedMeals.compactMap(\.cost).reduce(0, +) / Double(costedMeals.count), format: .currency(code: "USD"))
                    ForEach(costedMeals.prefix(10)) { log in
                        HStack {
                            Text(log.title).lineLimit(1)
                            Spacer()
                            if log.rating > 0 { Text(String(repeating: "★", count: log.rating)).font(.caption).foregroundStyle(Theme.gold) }
                            Text(log.cost ?? 0, format: .currency(code: "USD")).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Taste memory") {
                LabeledContent("Dishes rated", value: "\(logs.filter { $0.rating > 0 }.count)")
                let top = logs.filter { $0.rating == 5 }.prefix(5)
                if !top.isEmpty { ForEach(top) { Text("★ \($0.title)") } }
            }
        }.listRowBackground(RowGlass()) }
        .gardePage()
        .navigationTitle("Insights")
    }
}
