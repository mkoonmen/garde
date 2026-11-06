import SwiftUI

/// Highlights of the latest version, shown once after an update (and any time from More).
enum WhatsNew {
    static let version = "2.9"
    static let items: [(icon: String, title: String, text: String)] = [
        ("text.badge.plus", "Quick add", "Type or say everything you bought at once: \"eggs, 2 lb chicken thighs, a gallon of milk and spinach\". Kitchen → + → Quick add."),
        ("cart", "Shopping mode", "Big aisle-ordered list for the store. Tap to check off, screen stays on, and an estimate of what's left."),
        ("storefront", "Where to shop", "The list tells you which store is cheapest for most of it, from your own receipts, and deals show what you usually pay."),
        ("takeoutbag.and.cup.and.straw", "Meal prep", "A couple of batch dishes that cover the week, one efficient prep session, and the shopping list. Chef → Plan & host."),
        ("clock.badge.checkmark", "Dinner timeline", "Pick dishes and a serving time; Garde tells you when to start each, with reminders."),
        ("party.popper", "Thanksgiving ready", "Host a dinner has occasion presets and a turkey thaw calculator."),
        ("books.vertical", "Recipe book", "Search all your saved recipes and see which ones you can make right now."),
        ("doc.text.viewfinder", "Scan a recipe page", "Scan → Recipe reads a cookbook page or recipe card into your recipes. Or paste a link in Shared recipes."),
        ("arrow.left.arrow.right", "Instant swaps", "Classic substitutions (buttermilk, cream, eggs, wine…) answer instantly, even offline."),
        ("leaf.fill", "No-waste streak", "The Kitchen shows how long since you last threw food away, and how much food you have on hand."),
        ("checkmark.shield", "Safer allergies", "Photo scans warn about allergens, more hidden tree-nut dishes are caught, and onboarding asks which nuts you can eat."),
    ]
    /// Opens TestFlight, where testers can send feedback straight to the developer (no personal email shown in the app).
    static let feedbackURL = URL(string: "itms-beta://")!
}

struct WhatsNewView: View {
    var onDone: (() -> Void)? = nil
    var body: some View {
        List { Group {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("What's new in Garde \(WhatsNew.version)").font(.title2.weight(.bold)).fontDesign(.serif)
                    Text("Tonight's update, in short.").foregroundStyle(.secondary)
                }.padding(.vertical, 6)
            }
            Section {
                ForEach(WhatsNew.items, id: \.title) { i in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: i.icon).font(.title2).foregroundStyle(Theme.copper).frame(width: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(i.title).font(.headline)
                            Text(i.text).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 4)
                }
            }
            if let onDone {
                Section {
                    Button { onDone() } label: { Text("Let's cook").font(.headline).frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }.listRowBackground(Color.clear)
            }
        }.listRowBackground(RowGlass()) }
        .gardePage()
        .navigationTitle("What's new")
    }
}
