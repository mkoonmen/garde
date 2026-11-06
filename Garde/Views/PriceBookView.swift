import SwiftUI
import SwiftData

/// Every price you've paid, from receipts and scans: last, lowest, average, and which store is cheapest.
struct PriceBookView: View {
    @Query private var items: [PantryItem]
    @State private var query = ""
    @State private var entries: [PriceBook.Entry] = []

    private var shown: [PriceBook.Entry] {
        query.isEmpty ? entries : entries.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List { Group {
            if entries.isEmpty {
                ContentUnavailableView("No prices yet", systemImage: "tag",
                    description: Text("Scan a receipt or import Gmail receipts and every price you pay shows up here."))
            } else {
                let rising = entries.filter { $0.trend > 0.12 }.prefix(5)
                if query.isEmpty && !rising.isEmpty {
                    Section {
                        ForEach(Array(rising)) { e in
                            HStack {
                                Text(e.name)
                                Spacer()
                                Label("+\(Int((e.trend * 100).rounded()))%", systemImage: "arrow.up.right").foregroundStyle(.orange).font(.caption.weight(.semibold))
                            }
                        }
                    } header: { Text("Going up") } footer: { Text("Last price compared with your average.") }
                }
                Section("\(shown.count) items") {
                    ForEach(shown) { e in
                        NavigationLink { PriceHistoryView(entry: e) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(e.name).font(.body.weight(.medium)).lineLimit(1)
                                    Spacer()
                                    Text(e.last, format: .currency(code: "USD")).monospacedDigit()
                                }
                                HStack(spacing: 10) {
                                    Text("low \(e.lowest.formatted(.currency(code: "USD")))")
                                    Text("\(e.paid.count)× bought")
                                    if let c = e.cheapestStore { Text("cheapest: \(c)").foregroundStyle(.green) }
                                }.font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }.listRowBackground(RowGlass()) }
        .gardePage()
        .searchable(text: $query, prompt: "Search prices")
        .navigationTitle("Price book")
        .task { entries = PriceBook.entries(items) }
    }
}

struct PriceHistoryView: View {
    let entry: PriceBook.Entry
    var body: some View {
        List { Group {
            Section {
                LabeledContent("Last paid", value: entry.last.formatted(.currency(code: "USD")))
                LabeledContent("Lowest", value: entry.lowest.formatted(.currency(code: "USD")))
                LabeledContent("Average", value: entry.average.formatted(.currency(code: "USD")))
                if let c = entry.cheapestStore { LabeledContent("Cheapest store", value: c) }
            }
            Section("History") {
                ForEach(Array(entry.paid.enumerated()), id: \.offset) { _, p in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(p.store)
                            Text(p.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(p.price, format: .currency(code: "USD")).monospacedDigit()
                    }
                }
            }
        }.listRowBackground(RowGlass()) }
        .gardePage()
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
