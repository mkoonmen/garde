import SwiftUI
import SwiftData
import Charts

/// Where the money goes: cost per meal, waste, and what you keep throwing out.
struct InsightsView: View {
    @Query private var items: [PantryItem]
    @Query(sort: \CookLog.date, order: .reverse) private var logs: [CookLog]
    @Query private var receipts: [Receipt]
    @State private var range = 30
    @Query private var profiles: [KitchenProfile]
    @Query private var takeout: [TakeoutOrder]
    @State private var budgetText = ""
    @FocusState private var editingBudget: Bool
    private var monthSpent: Double {
        let start = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
        return receipts.filter { $0.date >= start }.compactMap(\.total).reduce(0, +)
    }

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
            if let card = ReportCard.make(items: items, logs: logs, takeout: takeout, spent: monthSpent, budget: profiles.first?.monthlyBudget ?? 0) {
                Section {
                    HStack(spacing: 16) {
                        Text(card.grade).font(.system(size: 54, weight: .heavy, design: .serif))
                            .foregroundStyle(card.points >= 80 ? Color.green : card.points >= 60 ? Color.orange : Color.red)
                            .frame(width: 70)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(card.notes, id: \.self) { Text($0).font(.subheadline) }
                        }
                    }.padding(.vertical, 4)
                } header: { Text("This month's report card") } footer: { Text("Waste, home cooking vs. takeout, and budget pace.") }
            }
            Picker("Range", selection: $range) {
                Text("30 days").tag(30); Text("90 days").tag(90); Text("Year").tag(365)
            }.pickerStyle(.segmented).listRowBackground(Color.clear)

            if let profile = profiles.first {
                Section {
                    LabeledContent("Monthly budget") {
                        HStack(spacing: 2) {
                            Text("$").foregroundStyle(.secondary)
                            TextField("Off", text: $budgetText)
                                .keyboardType(.decimalPad).focused($editingBudget).frame(maxWidth: 90)
                                .onChange(of: budgetText) { _, t in
                                    profile.monthlyBudget = max(0, Double(t.filter { $0.isNumber || $0 == "." }) ?? 0)
                                }
                        }.multilineTextAlignment(.trailing)
                    }
                    .onAppear { budgetText = profile.monthlyBudget > 0 ? String(Int(profile.monthlyBudget)) : "" }
                    if profile.monthlyBudget > 0 {
                        let used = monthSpent / profile.monthlyBudget
                        ProgressView(value: min(used, 1)) {
                            Text("\(monthSpent.formatted(.currency(code: "USD").precision(.fractionLength(0)))) of \(profile.monthlyBudget.formatted(.currency(code: "USD").precision(.fractionLength(0)))) this month")
                        }.tint(used > 1 ? .red : used > 0.85 ? .orange : .green)
                        let day = Double(Calendar.current.component(.day, from: .now))
                        let days = Double(Calendar.current.range(of: .day, in: .month, for: .now)?.count ?? 30)
                        // Early in the month one big shop would project wildly, so blend with the budget's daily rate.
                        let pace = day < 7 ? monthSpent + profile.monthlyBudget / days * (days - day) : monthSpent / day * days
                        Text(pace > profile.monthlyBudget
                             ? "On pace for \(pace.formatted(.currency(code: "USD").precision(.fractionLength(0)))), over budget."
                             : "On pace to stay under budget.")
                            .font(.caption).foregroundStyle(pace > profile.monthlyBudget ? .orange : .secondary)
                    }
                } header: { Text("Budget") }
            }

            let proteins = TasteProfile.rank(TasteProfile.proteins, home: logs, takeout: takeout)
            let styles = TasteProfile.rank(TasteProfile.styles, home: logs, takeout: takeout)
            if !proteins.isEmpty || !styles.isEmpty {
                Section {
                    if let avg = TasteProfile.average(logs) {
                        LabeledContent("Average home rating", value: String(format: "%.1f ★ over %d dishes", avg, logs.filter { $0.rating > 0 }.count))
                    }
                    if !proteins.isEmpty { tasteBar("Proteins", proteins) }
                    if !styles.isEmpty { tasteBar("Styles", styles) }
                    let homeCount = logs.count, outCount = takeout.count
                    if homeCount + outCount > 0 {
                        LabeledContent("Cooked vs. ordered", value: "\(homeCount) home · \(outCount) takeout")
                    }
                } header: { Text("Your taste") } footer: { Text("From your ratings and takeout receipts. The chef uses the same signals.") }
            }

            Section("Spending") {
                LabeledContent("Groceries", value: spent, format: .currency(code: "USD"))
                if weeklySpend.count > 1 {
                    Chart(weeklySpend, id: \.0) { BarMark(x: .value("Week", $0.0, unit: .weekOfYear), y: .value("Spent", $0.1)).foregroundStyle(Theme.accent) }
                        .frame(height: 140)
                }
            }

            Section {
                LabeledContent("Thrown out", value: "\(Plural.items(waste.tossedCount))")
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
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { editingBudget = false } } }
        .navigationTitle("Insights")
    }

    private func tasteBar(_ label: String, _ ranked: [(String, Int)]) -> some View {
        let top = Array(ranked.prefix(4)), total = max(top.map(\.1).reduce(0, +), 1)
        return VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(top.enumerated()), id: \.offset) { i, p in
                        Rectangle().fill([Theme.copper, Theme.accent, Color.teal, Color.purple][i % 4].opacity(0.85))
                            .frame(width: max(geo.size.width * CGFloat(p.1) / CGFloat(total) - 2, 4))
                    }
                }.clipShape(.capsule)
            }.frame(height: 10)
            HStack(spacing: 10) {
                ForEach(Array(top.enumerated()), id: \.offset) { i, p in
                    HStack(spacing: 4) {
                        Circle().fill([Theme.copper, Theme.accent, Color.teal, Color.purple][i % 4]).frame(width: 7, height: 7)
                        Text(p.0).font(.caption2)
                    }
                }
            }
        }.padding(.vertical, 4)
    }
}
