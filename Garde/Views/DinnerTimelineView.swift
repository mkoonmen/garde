import SwiftUI
import SwiftData
import UserNotifications

/// Several dishes, one serving time: works backwards so everything is ready together, with optional start reminders.
struct DinnerTimelineView: View {
    @Query(sort: \SavedRecipe.title) private var saved: [SavedRecipe]
    @State private var picked: Set<UUID> = []
    @State private var serveAt: Date = {
        let seven = Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: .now) ?? .now
        return seven > .now.addingTimeInterval(30 * 60) ? seven : Calendar.current.date(byAdding: .day, value: 1, to: seven) ?? seven
    }()
    @State private var extra: [(name: String, minutes: Int)] = []
    @State private var newName = ""
    @State private var newMinutes = 20
    @State private var reminders = false
    @State private var earlier = 0      // reminders still pending from a timeline set up before

    struct Step: Identifiable { let id = UUID(); let name: String; let minutes: Int; let start: Date }

    static func plan(_ dishes: [(String, Int)], serveAt: Date, buffer: Int = 5) -> [Step] {
        dishes.map { Step(name: $0.0, minutes: $0.1, start: serveAt.addingTimeInterval(-Double($0.1 + buffer) * 60)) }
            .sorted { $0.start < $1.start }
    }

    private var steps: [Step] {
        let dishes = saved.filter { picked.contains($0.id) }.map { ($0.title, max($0.minutes, 5)) } + extra.map { ($0.name, $0.minutes) }
        return Self.plan(dishes, serveAt: serveAt)
    }

    var body: some View {
        List { Group {
            if earlier > 0 && !reminders {
                Section {
                    Button("Cancel \(earlier) reminder\(earlier == 1 ? "" : "s") from an earlier timeline", systemImage: "bell.slash", role: .destructive) {
                        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: (0..<30).map { "timeline-\($0)" })
                        earlier = 0
                    }
                }
            }
            Section {
                DatePicker("Serve at", selection: $serveAt, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
            }
            Section("Dishes") {
                if saved.isEmpty && extra.isEmpty { Text("Save some recipes, or add a dish below.").foregroundStyle(.secondary) }
                ForEach(saved) { r in
                    Button {
                        if picked.contains(r.id) { picked.remove(r.id) } else { picked.insert(r.id) }
                    } label: {
                        HStack {
                            Image(systemName: picked.contains(r.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(picked.contains(r.id) ? .green : .secondary)
                            Text(r.title)
                            Spacer()
                            Text("\(r.minutes) min").foregroundStyle(.secondary).font(.caption)
                        }.contentShape(.rect)
                    }.buttonStyle(.plain)
                }
                ForEach(Array(extra.enumerated()), id: \.offset) { _, e in
                    HStack { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green); Text(e.name); Spacer(); Text("\(e.minutes) min").foregroundStyle(.secondary).font(.caption) }
                }
                .onDelete { extra.remove(atOffsets: $0) }
                HStack {
                    TextField("Other dish (e.g. roast potatoes)", text: $newName)
                    Stepper("\(newMinutes)m", value: $newMinutes, in: 5...480, step: 5).fixedSize()
                    Button("Add", systemImage: "plus.circle.fill") {
                        extra.append((newName.trimmingCharacters(in: .whitespaces), newMinutes)); newName = ""
                    }.labelStyle(.iconOnly).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if !steps.isEmpty {
                Section {
                    ForEach(steps) { s in
                        HStack(alignment: .firstTextBaseline) {
                            Text(s.start, format: .dateTime.hour().minute()).font(.headline.monospacedDigit()).foregroundStyle(Theme.copper).frame(width: 80, alignment: .leading)
                            VStack(alignment: .leading) {
                                Text("Start \(s.name)")
                                Text("\(s.minutes) min").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    HStack {
                        Text(serveAt, format: .dateTime.hour().minute()).font(.headline.monospacedDigit()).frame(width: 80, alignment: .leading)
                        Text("Serve").font(.headline)
                    }
                    Toggle("Remind me at each start", isOn: $reminders)
                        .onChange(of: reminders) { _, on in schedule(on) }
                } header: { Text("Timeline") } footer: { Text("Everything is timed to finish 5 minutes before serving so you can plate.") }
            }
        }.listRowBackground(RowGlass()) }
        .gardePage()
        .navigationTitle("Dinner timeline")
        .onChange(of: serveAt) { _, _ in if reminders { schedule(true) } }
        .onChange(of: steps.map(\.start)) { _, _ in if reminders { schedule(true) } }
        .task {
            let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
            earlier = pending.filter { $0.identifier.hasPrefix("timeline-") }.count
        }
    }

    private func schedule(_ on: Bool) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: (0..<30).map { "timeline-\($0)" })
        guard on else { return }
        for (i, s) in steps.enumerated() where s.start > .now {
            let c = UNMutableNotificationContent()
            c.title = "Start \(s.name) now"
            c.body = "\(s.minutes) minutes to go, serving at \(serveAt.formatted(date: .omitted, time: .shortened))."
            c.sound = .default
            let t = UNTimeIntervalNotificationTrigger(timeInterval: s.start.timeIntervalSinceNow, repeats: false)
            center.add(UNNotificationRequest(identifier: "timeline-\(i)", content: c, trigger: t))
        }
    }
}
