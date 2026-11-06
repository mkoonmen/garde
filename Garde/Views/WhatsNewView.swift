import SwiftUI

/// Highlights of the latest version, shown once after an update (and any time from More).
enum WhatsNew {
    static let version = "3.0"
    static let items: [(icon: String, title: String, text: String)] = [
        ("scalemass", "Know what remains", "Keep product names and recipe ingredients separate. Set a package size, use measured amounts while cooking, or choose Full, Half, Almost gone and Finished."),
        ("clock.arrow.circlepath", "Kitchen history", "See when food was added, opened, frozen or used. Undo a change while its inventory state is still current."),
        ("fork.knife", "Three dinner choices", "Use what's here, choose something quick, or revisit flavors you love. Start cooking, plan it for tomorrow, or ask for something easier from the Kitchen."),
        ("book.closed", "A cooking foundation", "Original basic recipes provide an immediate fallback. Recipe checks flag missing amounts and inconsistent instructions, and cooking pages show equipment and timing notes."),
        ("checklist", "A more useful list", "Planned dinners share the stock at home before adding combined shortages. Your usual products stay recognizable, with reasons for restocking and store preferences."),
        ("person.text.rectangle", "Your household, remembered", "More → Household memory keeps weeknight effort, spice, leftovers and favorite brands editable. Review cooking feedback and stop using a note whenever you like."),
        ("camera.viewfinder", "Less kitchen upkeep", "Receipt review flags likely existing items. An optional kitchen check helps confirm older stock, and backups include the new amounts, history and household memory."),
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
                    // Drawn by hand: a tinted system button rendered cream-on-cream inside this sheet.
                    Button { onDone() } label: {
                        Text("Let's cook").font(.headline).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(Theme.copper, in: .capsule)
                    }.buttonStyle(.plain)
                }.listRowBackground(Color.clear)
            }
        }.listRowBackground(RowGlass()) }
        .gardePage()
        .navigationTitle("What's new")
    }
}
