import SwiftUI
import SwiftData

/// A week of dinners planned around what expires first, with the missing groceries sent to the List.
struct MealPlanView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MealPlanEntry.day) private var plan: [MealPlanEntry]
    @Query(filter: #Predicate<PantryItem> { !$0.isUsedUp }) private var items: [PantryItem]
    @Query private var spices: [Spice]
    @Query private var profiles: [KitchenProfile]
    @Query private var logs: [CookLog]

    @State private var chef = ChefAI()
    @State private var days = 5
    @State private var notes = ""
    @State private var working = false
    @State private var message: String?

    private var upcoming: [MealPlanEntry] { plan.filter { $0.day >= Calendar.current.startOfDay(for: .now) } }

    var body: some View {
        List {
            Section {
                Stepper("Plan \(days) dinners", value: $days, in: 2...7)
                TextField("This week… (e.g. out Friday, steak night Saturday)", text: $notes, axis: .vertical)
                Button { Task { await makePlan() } } label: {
                    HStack { Spacer(); if working { ProgressView() } else { Label(upcoming.isEmpty ? "Plan my week" : "Re-plan", systemImage: "calendar.badge.plus") }; Spacer() }
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
        }
        .navigationTitle("Week plan")
    }

    private func makePlan() async {
        guard let profile = profiles.first else { return }
        working = true; message = nil; defer { working = false }
        do {
            let out = try await chef.planWeek(days: days, items: items, spices: spices, profile: profile, logs: logs, notes: notes)
            guard !out.dinners.isEmpty else { message = "Couldn't build a safe plan. Try again."; return }
            upcoming.filter { !$0.isCooked }.forEach { context.delete($0) }
            let start = Calendar.current.startOfDay(for: .now)
            var bought = 0
            for d in out.dinners.sorted(by: { $0.dayIndex < $1.dayIndex }).prefix(days) {
                let day = Calendar.current.date(byAdding: .day, value: max(0, min(d.dayIndex, days - 1)), to: start)!
                let r = d.recipe
                context.insert(MealPlanEntry(day: day, title: r.title, summary: r.summary, minutes: r.minutes, servings: r.servings,
                                             ingredients: r.ingredients, steps: r.steps, needToBuy: d.needToBuy))
                ShoppingBrain.add(needToBuy: d.needToBuy, for: r.title, day: day, context: context)
                bought += d.needToBuy.count
            }
            message = "Planned \(min(out.dinners.count, days)) dinners. \(bought) items added to your List."
                + (out.blocked > 0 ? " \(out.blocked) dropped for allergens." : "")
        } catch {
            message = "The planner got stuck: \(error.localizedDescription)"
        }
    }
}
