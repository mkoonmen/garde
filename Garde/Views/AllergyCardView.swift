import SwiftUI
import SwiftData
import FoundationModels

/// "Show this to your server": a full-screen allergy card, translated on the phone if you're abroad.
struct AllergyCardView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [KitchenProfile]
    @State private var language = "English"
    @State private var translated: String?
    @State private var working = false
    @State private var translateError: String?

    private let languages = ["English", "Spanish", "Italian", "French", "Portuguese", "German", "Japanese"]

    private var allergies: [String] { Array(Set(profiles.flatMap(\.allergies))).sorted() }

    /// Plain English the server can act on. "Tree nuts except almonds, hazelnuts" reads naturally as is.
    var english: String {
        guard !allergies.isEmpty else { return "No allergies saved yet." }
        let list = allergies.map { "• " + $0.replacingOccurrences(of: " except ", with: " (I CAN have ") + ($0.contains(" except ") ? ")" : "") }
        return "I have a serious food allergy.\n\nPlease make sure my food does not contain, and is not prepared with:\n\n" + list.joined(separator: "\n")
            + "\n\nThis includes oils, sauces, garnishes and shared fryers or surfaces. Thank you!"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label("Allergy", systemImage: "exclamationmark.triangle.fill")
                        .font(.title.weight(.heavy)).foregroundStyle(.red)
                    Text(language == "English" ? english : (translated ?? english))
                        .font(.title2.weight(.semibold)).textSelection(.enabled)
                    if let translateError { Text(translateError).font(.caption).foregroundStyle(.orange) }
                    if language != "English", translated != nil {
                        Divider()
                        Text(english).font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white, in: .rect(cornerRadius: 24))
                .foregroundStyle(.black)
                .padding()
            }
            .background(Color(red: 0.98, green: 0.96, blue: 0.92).ignoresSafeArea())
            .navigationTitle("Allergy card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Language", selection: $language) { ForEach(languages, id: \.self) { Text($0).tag($0) } }
                    } label: { if working { ProgressView() } else { Label(language, systemImage: "globe") } }
                }
            }
            .task(id: language) { await translate(to: language) }
        }
    }

    private func translate(to lang: String) async {
        translated = nil; translateError = nil
        guard lang != "English" else { return }
        guard ChefAI().state == .available else { translateError = "Translation needs Apple Intelligence; showing English."; return }
        working = true; defer { working = false }
        let session = ChefEngine.shared.session(instructions: "You translate short, important allergy notes for restaurant staff. Translate exactly and completely; keep every food listed. Output only the translation.")
        let result = try? await session.reply(to: "Translate into \(lang):\n\n\(english)")
        guard lang == language, !Task.isCancelled else { return }   // the language changed while this was running
        if let result { translated = result } else { translateError = "Couldn't translate; showing English." }
    }
}
