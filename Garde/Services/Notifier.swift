import Foundation
import UserNotifications

/// Local (on-device) reminders for food that's about to expire.
enum Notifier {
    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Rebuilds all expiration reminders. Each item gets one alert at 9 AM,
    /// `warningDays` before it expires.
    static func reschedule(items: [PantryItem], warningDays: Int) {
        let center = UNUserNotificationCenter.current()
        let cal = Calendar.current
        var keep: Set<String> = []
        for item in items where !item.isUsedUp {
            guard let exp = item.expirationDate,
                  let alertDay = cal.date(byAdding: .day, value: -warningDays, to: exp),
                  alertDay > .distantPast else { continue }
            var fire = cal.dateComponents([.year, .month, .day], from: alertDay)
            fire.hour = 9
            guard let fireDate = cal.date(from: fire), fireDate > .now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "\(item.name) expires soon"
            content.body = warningDays == 1 ? "Use it by tomorrow. Open the chef for ideas." : "Use it within \(warningDays) days. Open the chef for ideas."
            content.sound = .default
            content.userInfo = ["mustUse": item.name]   // tapping opens the Chef with this item pre-selected
            let trigger = UNCalendarNotificationTrigger(dateMatching: fire, repeats: false)
            let id = "exp-" + item.id.uuidString
            keep.insert(id)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))   // same id replaces the old one
        }
        // Drop alerts for food that's gone. Cook-mode timers (no "exp-" prefix) are left alone.
        let current = keep
        center.getPendingNotificationRequests { pending in
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("exp-") && !current.contains($0) })
        }
    }

    /// For each planned dinner that needs something from the freezer, a 7 PM reminder the night before
    /// ("Move the chicken thighs to the fridge for tomorrow's piccata"). Same-day plans get a reminder now-ish if it's early.
    static func scheduleThawReminders(plan: [MealPlanEntry], items: [PantryItem]) {
        let center = UNUserNotificationCenter.current()
        let cal = Calendar.current
        let frozen = items.filter { !$0.isUsedUp && $0.location == .freezer }
        var keep: Set<String> = []
        for entry in plan where !entry.isCooked && entry.day >= cal.startOfDay(for: .now) {
            let text = (entry.ingredients + [entry.title]).joined(separator: " ").lowercased()
            let needed = frozen.filter { ShoppingBrain.appears($0.name, in: text) }
            guard !needed.isEmpty,
                  let eve = cal.date(byAdding: .day, value: -1, to: entry.day),
                  let fire = cal.date(bySettingHour: 19, minute: 0, second: 0, of: eve), fire > .now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Thaw for tomorrow"
            content.body = "Move \(needed.map(\.name).joined(separator: ", ")) from the freezer to the fridge for \(entry.title)."
            content.sound = .default
            let id = "thaw-" + entry.id.uuidString
            keep.insert(id)
            center.add(UNNotificationRequest(identifier: id, content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false)))
        }
        let current = keep
        center.getPendingNotificationRequests { pending in
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("thaw-") && !current.contains($0) })
        }
    }
}

/// Routes a tapped expiration reminder to the Chef tab with that item already ticked as "must use".
@MainActor
@Observable
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()
    var tab = 0
    var mustUse: String?
    var mood: String?          // e.g. from the spice rack: "Something that shows off smoked paprika"

    func install() { UNUserNotificationCenter.current().delegate = self }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let name = response.notification.request.content.userInfo["mustUse"] as? String
        await MainActor.run {
            guard let name else { return }
            self.mustUse = name
            self.tab = 2
        }
    }

    /// Show reminders (and cook timers) even while Garde is open.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
