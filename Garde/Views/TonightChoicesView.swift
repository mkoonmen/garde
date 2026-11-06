import SwiftUI
import SwiftData

struct TonightChoicesView: View {
    @Environment(\.modelContext) private var context
    let items: [PantryItem]
    let spices: [Spice]
    let profile: KitchenProfile?
    let logs: [CookLog]
    @State private var daily = DailyPick.shared
    @State private var cooking: DailyPick.Pick?
    @State private var message: String?
    @State private var plannedID: UUID?
    private var inventorySignature: String {
        let food = items.map { "\($0.id)/\($0.availableLabel)/\($0.ingredientName)/\($0.daysLeft ?? 999)" }.sorted().joined(separator: "|")
        return food + (profile?.allergies.joined(separator: "|") ?? "") + (profile?.householdMemory.joined(separator: "|") ?? "") + String(profile?.weeknightMinutes ?? 30) + logs.map { $0.id.uuidString }.joined()
    }
    var body: some View {
        Section {
            ForEach(daily.choices) { choice in
                VStack(alignment: .leading, spacing: 8) {
                    Text(choice.mode.rawValue).font(.caption.weight(.semibold)).foregroundStyle(Theme.copper)
                    NavigationLink {
                        RecipeDetailView(title: choice.pick.title, summary: choice.pick.summary, minutes: choice.pick.minutes,
                                         servings: choice.pick.servings, ingredients: choice.pick.ingredients, steps: choice.pick.steps)
                    } label: { RecipeRow(title: choice.pick.title, summary: choice.pick.summary, minutes: choice.pick.minutes) }
                    Text(choice.explanation).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Cook this") { cooking = choice.pick }
                        Button("Tomorrow instead") { planTomorrow(choice.pick) }
                    }.buttonStyle(.bordered).controlSize(.small)
                }.padding(.vertical, 4)
            }
            if daily.choices.isEmpty { Text(daily.problem ?? "Choose your household preferences in More to get started.").foregroundStyle(.secondary) }
            Button("Something easier", systemImage: "timer") { refresh(easier: true) }.disabled(daily.working)
            if let problem = daily.problem, !daily.choices.isEmpty { Text(problem).font(.caption).foregroundStyle(.secondary) }
            if let message { Text(message).font(.caption) }
            if plannedID != nil { Button("Undo tomorrow’s plan") { undoPlan() } }
        } header: {
            HStack {
                Text("Tonight’s choices")
                Spacer()
                Button { refresh() } label: { if daily.working { ProgressView() } else { Image(systemName: "arrow.clockwise") } }.disabled(daily.working)
            }
        }
        .task(id: inventorySignature) { await daily.refreshIfNeeded(items: items, spices: spices, profile: profile, logs: logs) }
        .fullScreenCover(item: $cooking) { pick in
            let matched = items.filter { item in pick.ingredients.contains { FoodIdentity.matches(RecipeScaler.foodName($0), item.ingredientName) } }
            CookModeView(title: pick.title, steps: pick.steps, ingredients: pick.ingredients, servings: pick.servings,
                         usedItems: matched, estimatedCost: nil) { cooking = nil }
        }
    }
    private func refresh(easier: Bool = false) {
        Task { await daily.refreshIfNeeded(items: items, spices: spices, profile: profile, logs: logs, force: true, easier: easier) }
    }
    private func planTomorrow(_ pick: DailyPick.Pick) {
        let day = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        let start = Calendar.current.startOfDay(for: day)
        do {
            let plans = try context.fetch(FetchDescriptor<MealPlanEntry>())
            guard !plans.contains(where: { $0.day == start && $0.title == pick.title }) else { message = "Already planned for tomorrow."; return }
            let entry = MealPlanEntry(day: day, title: pick.title, summary: pick.summary, minutes: pick.minutes, servings: pick.servings,
                                      ingredients: pick.ingredients, steps: pick.steps, needToBuy: [])
            context.insert(entry)
            plannedID = entry.id
            try context.save()
            try MealShopping.reconcile(context: context)
            message = "Planned for tomorrow. The List includes the amounts needed."
        } catch { message = error.localizedDescription }
    }
    private func undoPlan() {
        do {
            if let entry = try context.fetch(FetchDescriptor<MealPlanEntry>()).first(where: { $0.id == plannedID }) { context.delete(entry) }
            try context.save()
            try MealShopping.reconcile(context: context)
            plannedID = nil; message = "Tomorrow’s plan was removed."
        } catch { message = error.localizedDescription }
    }

}
