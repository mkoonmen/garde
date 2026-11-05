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
}
