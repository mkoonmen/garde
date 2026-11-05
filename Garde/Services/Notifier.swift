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
        center.removeAllPendingNotificationRequests()
        let cal = Calendar.current
        for item in items where !item.isUsedUp {
            guard let exp = item.expirationDate,
                  let alertDay = cal.date(byAdding: .day, value: -warningDays, to: exp),
                  var fire = Optional(cal.dateComponents([.year, .month, .day], from: alertDay)) else { continue }
            fire.hour = 9
            guard let fireDate = cal.date(from: fire), fireDate > .now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "\(item.name) expires soon"
            content.body = warningDays == 1 ? "Use it by tomorrow. Open the chef for ideas." : "Use it within \(warningDays) days. Open the chef for ideas."
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: fire, repeats: false)
            center.add(UNNotificationRequest(identifier: item.id.uuidString, content: content, trigger: trigger))
        }
    }
}
