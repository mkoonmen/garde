import SwiftUI
import SwiftData

/// "What can I mix tonight?": cocktails from the bottles you own and what's in the kitchen.
struct MixView: View {
    @Query(sort: \BarBottle.name) private var bottles: [BarBottle]
    @Query(filter: #Predicate<PantryItem> { !$0.isUsedUp }) private var items: [PantryItem]
    @Query private var profiles: [KitchenProfile]
    @State private var mood = ""
    @State private var drinks: [Cocktail] = []
    @State private var working = false
    @State private var message: String?
    @State private var flight: Flight?
    @State private var flighting = false

    private let moods = ["Classic", "Refreshing", "Stirred & strong", "Low-ABV", "Fall", "Tiki"]

    var body: some View {
        List { Group {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack { ForEach(moods, id: \.self) { m in Button(m) { mood = mood == m ? "" : m }.buttonStyle(.bordered).tint(mood == m ? Theme.copper : .secondary) } }
                }
                Button { Task { await mix() } } label: {
                    HStack { Spacer(); if working { ProgressView() } else { Label("Mix something", systemImage: "wineglass") }; Spacer() }
                }.disabled(working)
            } footer: { Text("Uses \(bottles.filter { $0.count > 0 }.count) bottles from your bar plus citrus, sugar and herbs from your kitchen.") }
            Section {
                Button { Task { await planFlight() } } label: {
                    HStack { Spacer(); if flighting { ProgressView() } else { Label("Plan a tasting flight", systemImage: "list.number") }; Spacer() }
                }.disabled(flighting || bottles.filter { $0.count > 0 }.count < 2)
                if let flight {
                    ForEach(Array(flight.pours.enumerated()), id: \.offset) { i, p in
                        HStack(alignment: .top, spacing: 10) { Text("\(i + 1)").font(.headline).foregroundStyle(Theme.copper); Text(p) }
                    }
                    Text(flight.why).font(.subheadline).foregroundStyle(.secondary)
                    if !flight.snacks.isEmpty { Label("Set out: \(flight.snacks.joined(separator: ", "))", systemImage: "fork.knife").font(.caption) }
                }
            } footer: { Text("Side-by-side tasting from your own bottles, lightest to boldest.") }
            if let message { Section { Text(message).foregroundStyle(.orange) } }
            ForEach(Array(drinks.enumerated()), id: \.offset) { _, d in
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(d.name).gardeHeading(.title3)
                        ForEach(d.spec, id: \.self) { Text("• \($0)") }
                        Text(d.method).font(.subheadline).foregroundStyle(.secondary)
                        if !d.missing.isEmpty { Label("Need: \(d.missing.joined(separator: ", "))", systemImage: "cart").font(.caption).foregroundStyle(.orange) }
                    }.padding(.vertical, 4)
                }
            }
        }.listRowBackground(RowGlass()) }
        .gardePage()
        .navigationTitle("Mix tonight")
    }

    private func planFlight() async {
        guard let profile = profiles.first else { message = "Set up your kitchen profile first."; return }
        let chef = ChefAI()
        if case .unavailable(let why) = chef.state { message = why; return }
        flighting = true; message = nil; defer { flighting = false }
        do { flight = try await chef.flight(bottles: bottles, profile: profile) }
        catch { message = "Couldn't plan the flight: \(error.localizedDescription)" }
    }

    private func mix() async {
        guard let profile = profiles.first else { message = "Set up your kitchen profile first."; return }
        let chef = ChefAI()
        if case .unavailable(let why) = chef.state { message = why; return }
        working = true; message = nil; defer { working = false }
        do {
            let out = try await chef.cocktails(bottles: bottles, items: items, profile: profile, mood: mood)
            withAnimation { drinks = out }
            if out.isEmpty { message = "No safe drinks came back. Try another mood." }
        } catch { message = "The bartender got stuck: \(error.localizedDescription)" }
    }
}
