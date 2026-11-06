import SwiftUI

/// Highlights of the latest version, shown once after an update (and any time from More).
enum WhatsNew {
    static let version = "2.8"
    static let items: [(icon: String, title: String, text: String)] = [
        ("sun.max", "Tonight's idea", "Each day the Kitchen tab shows one dinner idea built around what expires first. Tapping an expiration reminder opens the Chef with that item ready to use."),
        ("bag", "Takeout favorites", "Your DoorDash, Uber Eats and restaurant receipts from Gmail become a list of favorite dishes. Tap Cook it for a homemade version. Chef → Takeout favorites."),
        ("tag", "Price book", "Every price you've paid, the lowest, and which store is cheapest. Your shopping list shows last price too. More → Price book."),
        ("person.2", "Scale & swap", "Change servings on any recipe and every amount rescales. Tap ⇄ next to an ingredient for an allergy-safe substitute."),
        ("fork.knife", "Plate it like a restaurant", "Every recipe can show you fine-dining plating: sauce, height, placement and a finishing touch."),
        ("party.popper", "Host a dinner", "Guests, occasion and their allergies → a make-ahead menu, prep timeline and shopping list. Chef → Host a dinner."),
        ("wineglass", "Mix tonight", "Cocktails from the bottles in your bar and the citrus and herbs in your kitchen, plus a guided tasting flight (bourbon night!). More → Bar & cellar."),
        ("leaf", "In season & cook again", "Local produce for this month, and dishes you loved but haven't made in a while, on the Chef tab."),
        ("checklist", "Mise en place", "Cook mode starts with a checklist so everything's out before step one."),
        ("dollarsign.circle", "Grocery budget", "Set a monthly budget in Insights and see your pace. Ask Siri \"How's my grocery budget in Garde\"."),
        ("envelope", "Cleaner Gmail receipts", "Only real grocery receipts are imported now. Old junk was cleaned up automatically."),
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
