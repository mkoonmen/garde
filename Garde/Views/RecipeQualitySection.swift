import SwiftUI
import SwiftData

struct RecipeQualitySection: View {
    @Query private var logs: [CookLog]
    @Query private var profiles: [KitchenProfile]
    let recipe: RecipeIdea
    private var check: RecipeFoundation.Check { RecipeFoundation.check(recipe) }
    private var equipment: [String] {
        let text = recipe.steps.joined(separator: " ").lowercased()
        return ["skillet", "saucepan", "oven", "baking tray", "blender", "thermometer"].filter { text.contains($0) }
    }
    var body: some View {
        Section {
            if !equipment.isEmpty { Label(equipment.joined(separator: ", ").capitalized, systemImage: "frying.pan") }
            if RecipeFoundation.basics.contains(where: { $0.title == recipe.title && $0.ingredients == recipe.ingredients && $0.steps == recipe.steps }) {
                Text("Garde basic method · total time includes preparation").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(logs.filter { $0.title.caseInsensitiveCompare(recipe.title) == .orderedSame && !$0.wouldChange.isEmpty && !(profiles.first?.ignoredFeedbackIDs.contains($0.id.uuidString) ?? false) }.prefix(3)) { log in
                Label("Your cooking note: " + log.wouldChange, systemImage: "note.text").font(.caption)
            }
            ForEach(check.errors + check.notes, id: \.self) { note in
                Label(note, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
            }
            Link("Food-temperature guidance (FDA)", destination: RecipeFoundation.temperatureSource).font(.caption)
        } header: { Text("Before cooking") }
    }
}
