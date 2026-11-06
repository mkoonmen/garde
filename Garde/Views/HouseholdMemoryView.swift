import SwiftUI
import SwiftData

struct HouseholdMemoryView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [KitchenProfile]
    @Query(sort: \CookLog.date, order: .reverse) private var logs: [CookLog]
    var body: some View {
        Group {
            if let profile = profiles.first { HouseholdMemoryForm(profile: profile, logs: logs) }
            else { ProgressView().task { context.insert(KitchenProfile()) } }
        }
    }
}

private struct HouseholdMemoryForm: View {
    @Bindable var profile: KitchenProfile
    let logs: [CookLog]
    private var feedback: [CookLog] {
        logs.filter { !$0.wouldChange.isEmpty && !profile.ignoredFeedbackIDs.contains($0.id.uuidString) }
    }
    var body: some View {
        Form {
            Section("Everyday cooking") {
                Stepper("Weeknights: \(profile.weeknightMinutes) minutes", value: $profile.weeknightMinutes, in: 10...90, step: 5)
                Picker("Spice", selection: $profile.spicePreference) {
                    ForEach(["Mild", "Medium", "Hot"], id: \.self) { Text($0).tag($0) }
                }
                Picker("Leftovers", selection: $profile.leftoverPreference) {
                    ForEach(["Enjoy leftovers", "Lunch the next day", "Prefer a fresh dinner"], id: \.self) { Text($0).tag($0) }
                }
            }
            Section("Specific things to remember") {
                TagEditor(tags: $profile.householdMemory, placeholder: "e.g. Less lemon in chicken piccata")
            }
            Section("Favorite brands") { TagEditor(tags: $profile.preferredBrands, placeholder: "Add a brand") }
            Section {
                TextField("Preferred grocery store", text: $profile.preferredStore)
                Toggle("Suggest an extra store for savings", isOn: $profile.allowExtraStore)
                if profile.allowExtraStore {
                    TextField("Minimum estimated savings", value: $profile.minimumExtraStoreSavings, format: .currency(code: "USD")).keyboardType(.decimalPad)
                }
            } header: { Text("Shopping trips") } footer: {
                Text("Store suggestions use your recorded purchase prices. They are estimates and may differ from current prices.")
            }
            Section {
                ForEach(feedback.prefix(30)) { log in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(log.title).font(.headline)
                        Text(log.wouldChange)
                        Button("Edit as a household instruction") {
                            let instruction = log.title + ": " + log.wouldChange
                            if !profile.householdMemory.contains(instruction) { profile.householdMemory.append(instruction) }
                            profile.ignoredFeedbackIDs.append(log.id.uuidString)
                        }
                        Button("Stop using this feedback", role: .destructive) { profile.ignoredFeedbackIDs.append(log.id.uuidString) }
                    }
                }
            } header: { Text("Feedback used by the chef") } footer: {
                Text("Delete a household instruction to forget it. Stopping feedback keeps the cooking journal entry and removes it from future chef prompts.")
            }
            if !profile.ignoredFeedbackIDs.isEmpty {
                Section { Button("Use cooking feedback again") { profile.ignoredFeedbackIDs = [] } }
            }
        }
        .gardePage().navigationTitle("Chef memory")
    }
}
