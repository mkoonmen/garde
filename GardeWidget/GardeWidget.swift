import WidgetKit
import SwiftUI
import SwiftData

struct GardeEntry: TimelineEntry {
    let date: Date
    let expiring: [(name: String, days: Int?)]
    let dinner: String?
}

struct GardeProvider: TimelineProvider {
    func placeholder(in context: Context) -> GardeEntry {
        GardeEntry(date: .now, expiring: [("Chicken thighs", 1), ("Spinach", 2), ("Brie", 3)], dinner: "Lemon garlic chicken")
    }
    func getSnapshot(in context: Context, completion: @escaping (GardeEntry) -> Void) { completion(load()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<GardeEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .hour, value: 3, to: .now)!
        completion(Timeline(entries: [load()], policy: .after(next)))
    }

    private func load() -> GardeEntry {
        let ctx = ModelContext(GardeStore.container)
        let items = ((try? ctx.fetch(FetchDescriptor<PantryItem>(predicate: #Predicate { !$0.isUsedUp }))) ?? [])
            .filter { $0.expirationDate != nil }
            .sorted { ($0.daysLeft ?? 99) < ($1.daysLeft ?? 99) }
            .prefix(4).map { (name: $0.name, days: $0.daysLeft) }
        let today = Calendar.current.startOfDay(for: .now)
        let shared = UserDefaults(suiteName: GardeStore.appGroup)
        let idea = shared?.string(forKey: "dailyPick.day") == GardeStore.dayKey ? shared?.string(forKey: "dailyPick.title") : nil
        let dinner = (try? ctx.fetch(FetchDescriptor<MealPlanEntry>(predicate: #Predicate { $0.day == today })))?.first?.title ?? idea
        return GardeEntry(date: .now, expiring: Array(items), dinner: dinner)
    }
}

struct GardeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GardeEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.dinner.map { "Tonight: \($0)" } ?? "Use first").font(.headline).lineLimit(1)
                ForEach(entry.expiring.prefix(2), id: \.name) { Text("\($0.name) · \(Theme.expiryText($0.days))").font(.caption).lineLimit(1) }
            }
        case .accessoryInline:
            Text(entry.dinner.map { "Tonight: \($0)" } ?? entry.expiring.first.map { "\($0.name): \(Theme.expiryText($0.days))" } ?? "Garde")
        default:
            VStack(alignment: .leading, spacing: 6) {
                if let dinner = entry.dinner {
                    Label(dinner, systemImage: "frying.pan").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent).lineLimit(1)
                } else {
                    Text("Use these first").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                }
                if entry.expiring.isEmpty { Text("Nothing expiring soon").font(.caption).foregroundStyle(.secondary) }
                ForEach(entry.expiring.prefix(family == .systemSmall ? 3 : 4), id: \.name) { item in
                    HStack {
                        Circle().fill(Theme.expiryColor(item.days)).frame(width: 7, height: 7)
                        Text(item.name).font(.caption).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(Theme.expiryText(item.days)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

@main
struct GardeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GardeWidget", provider: GardeProvider()) { entry in
            GardeWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Garde")
        .description("Tonight's dinner and what to use first.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}
