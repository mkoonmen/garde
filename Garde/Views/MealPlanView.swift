import SwiftUI
import SwiftData

/// A week of dinners planned around what expires first, with the missing groceries sent to the List.
struct MealPlanView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MealPlanEntry.day) private var plan: [MealPlanEntry]
    @Query(filter: #Predicate<PantryItem> { !$0.isUsedUp }) private var items: [PantryItem]
    private var frozen: [PantryItem] { items.filter { $0.location == .freezer } }
    private func fromFreezer(_ e: MealPlanEntry) -> [String] {
        let text = (e.ingredients + [e.title]).joined(separator: " ").lowercased()
        return frozen.filter { ShoppingBrain.appears($0.name, in: text) }.map(\.name)
    }
    @Query private var spices: [Spice]
    @Query private var profiles: [KitchenProfile]
    @Query private var logs: [CookLog]

    @State private var chef = ChefAI()
    @State private var days = 5
    @State private var notes = ""
    @State private var fakeOut = true
    @Query private var takeout: [TakeoutOrder]
    @State private var working = false
    @State private var message: String?
    @State private var step = ""

    private var upcoming: [MealPlanEntry] { plan.filter { $0.day >= Calendar.current.startOfDay(for: .now) } }

    var body: some View {
        List { Group {
            Section {
                Stepper("Plan \(days) dinners", value: $days, in: 2...7)
                TextField("This week… (e.g. out Friday, steak night Saturday)", text: $notes, axis: .vertical)
                if !takeout.isEmpty { Toggle("Fake-out night (homemade takeout favorite)", isOn: $fakeOut) }
                Button { Task { await makePlan() } } label: {
                    HStack { Spacer(); if working { ProgressView(step.isEmpty ? "Planning…" : step) } else { Label(upcoming.isEmpty ? "Plan my week" : "Re-plan", systemImage: "calendar.badge.plus") }; Spacer() }
                        .font(.headline)
                }.disabled(working || chef.state != .available)
            } footer: { Text("Uses what expires first, then adds whatever's missing to your List.") }

            if let message { Section { Text(message).font(.footnote) } }

            ForEach(upcoming) { entry in
                Section(entry.day.formatted(.dateTime.weekday(.wide).month().day())) {
                    NavigationLink {
                        RecipeDetailView(title: entry.title, summary: entry.summary, minutes: entry.minutes, servings: entry.servings,
                                         ingredients: entry.ingredients, steps: entry.steps)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.title).font(.headline).strikethrough(entry.isCooked)
                                if entry.isCooked { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                            }
                            Text(entry.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            let n = Nutrition.estimate(ingredients: entry.ingredients).perServing(entry.servings)
                            if n.isReliable {
                                Text("≈ \(Int(n.kcal.rounded())) kcal · \(Int(n.protein.rounded()))g protein per serving").font(.caption).foregroundStyle(.secondary)
                            }
                            let thaw = fromFreezer(entry)
                            if !thaw.isEmpty {
                                Label("Thaw the night before: \(thaw.joined(separator: ", "))", systemImage: "snowflake").font(.caption).foregroundStyle(.blue)
                            }
                            if !entry.needToBuy.isEmpty {
                                Label("Buy: \(entry.needToBuy.joined(separator: ", "))", systemImage: "cart").font(.caption).foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    .swipeActions {
                        Button("Remove", systemImage: "trash", role: .destructive) { context.delete(entry) }
                        Button(entry.isCooked ? "Not cooked" : "Cooked", systemImage: "checkmark") { entry.isCooked.toggle() }.tint(.green)
                    }
                }
            }
        }.listRowBackground(RowGlass()) }
        .gardePage()
        .navigationTitle("Week plan")
        .toolbar {
            if !upcoming.isEmpty {
                ShareLink(item: "This week's dinners\n\n" + upcoming.prefix(7).map { "\($0.day.formatted(.dateTime.weekday(.wide))): \($0.title)" }.joined(separator: "\n") + "\n\nFrom Garde") {
                    Label("Share plan", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private func makePlan() async {
        guard let profile = profiles.first else { return }
        working = true; message = nil; defer { working = false }
        do {
            step = "Sketching the week…"
            let out = try await chef.planWeek(days: days, items: items, spices: spices, profile: profile, logs: logs, notes: notes + fakeOutNote) { i, n in
                step = "Writing dinner \(i) of \(n)…"
            }
            step = ""
            guard !out.dinners.isEmpty else { message = "Couldn't build a safe plan. Try again."; return }
            upcoming.filter { !$0.isCooked }.forEach { context.delete($0) }
            let start = Calendar.current.startOfDay(for: .now)
            let cookedDays = Set(upcoming.filter(\.isCooked).map(\.day))
            var bought = 0
            for d in out.dinners.sorted(by: { $0.dayIndex < $1.dayIndex }).prefix(days) {
                let day = Calendar.current.date(byAdding: .day, value: max(0, min(d.dayIndex, days - 1)), to: start)!
                if cookedDays.contains(day) { continue }   // already cooked something that day
                let r = d.recipe
                context.insert(MealPlanEntry(day: day, title: r.title, summary: r.summary, minutes: r.minutes, servings: r.servings,
                                             ingredients: r.ingredients, steps: r.steps, needToBuy: d.needToBuy))
                ShoppingBrain.add(needToBuy: d.needToBuy, for: r.title, day: day, context: context)
                bought += d.needToBuy.count
            }
            Notifier.scheduleThawReminders(plan: (try? context.fetch(FetchDescriptor<MealPlanEntry>())) ?? [], items: items)
            message = "Planned \(out.dinners.count) dinners. \(Plural.items(bought)) added to your List."
                + (out.blocked > 0 ? " \(out.blocked) dropped for allergens." : "")
        } catch {
            message = "The planner got stuck: \(error.localizedDescription)"
        }
    }

    /// Asks for one dinner that recreates something you order a lot.
    private var fakeOutNote: String {
        guard fakeOut, !takeout.isEmpty else { return "" }
        let top = Takeout.favorites(takeout).dishes.prefix(5).map(\.0).joined(separator: ", ")
        return " Make one night a homemade \"fake-out\" of a takeout favorite: \(top)."
    }
}
