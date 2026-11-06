import Foundation
import UserNotifications

/// Local (on-device) reminders for food that's about to expire.
enum Notifier {
    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Rebuilds all expiration reminders: one alert per day at 9 AM listing what to use (iOS keeps at most 64 pending
    /// notifications, so one per item would silently drop some). At most 40 days are scheduled.
    static func reschedule(items: [PantryItem], warningDays: Int) {
        let center = UNUserNotificationCenter.current()
        let cal = Calendar.current
        var byDay: [Date: [PantryItem]] = [:]
        for item in items where !item.isUsedUp && item.location != .freezer {
            guard let exp = item.expirationDate, let alertDay = cal.date(byAdding: .day, value: -warningDays, to: exp) else { continue }
            let day = cal.startOfDay(for: alertDay)
            guard day.addingTimeInterval(9 * 3600) > .now else { continue }
            byDay[day, default: []].append(item)
        }
        var keep: Set<String> = []
        for (day, list) in byDay.sorted(by: { $0.key < $1.key }).prefix(40) {
            let names = list.map(\.name)
            let content = UNMutableNotificationContent()
            content.title = names.count == 1 ? "\(names[0]) expires soon"
                : "\(names.prefix(2).joined(separator: ", "))\(names.count > 2 ? " and \(names.count - 2) more" : "") expire soon"
            content.body = (warningDays == 1 ? "Use by tomorrow." : "Use within \(warningDays) days.") + " Tap for recipe ideas."
            content.sound = .default
            content.userInfo = ["mustUse": names[0]]   // tapping opens the Chef with the first one pre-selected
            var fire = cal.dateComponents([.year, .month, .day], from: day); fire.hour = 9
            let id = "exp-" + day.formatted(.iso8601.year().month().day())
            keep.insert(id)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: fire, repeats: false)))
        }
        // Drop old per-item alerts and days with nothing left. Cook-mode timers (no "exp-" prefix) are left alone.
        let current = keep
        center.getPendingNotificationRequests { pending in
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("exp-") && !current.contains($0) })
        }
    }

    /// "Leftover piccata for lunch?" at 11:30 the next day.
    static func leftoverLunch(title: String, itemID: UUID) {
        guard UserDefaults.standard.object(forKey: "leftoverNudge") as? Bool ?? true else { return }
        let c = UNMutableNotificationContent()
        c.title = "Leftovers for lunch?"
        c.body = "You've got \(title) in the fridge. It's best within 3–4 days."
        c.sound = .default
        c.userInfo = ["mustUse": "\(title) (leftovers)"]
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) else { return }
        var when = Calendar.current.dateComponents([.year, .month, .day], from: tomorrow); when.hour = 11; when.minute = 30
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "leftover-" + itemID.uuidString, content: c,
                                                                     trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false)))
    }

    /// Sunday 5 PM nudge to plan the week, with how much is expiring. Off when the setting is off.
    static func scheduleWeeklyNudge(items: [PantryItem]) {
        let center = UNUserNotificationCenter.current()
        guard UserDefaults.standard.object(forKey: "weeklyNudge") as? Bool ?? true else {
            center.removePendingNotificationRequests(withIdentifiers: ["weekly-plan"]); return
        }
        let soon = items.filter { !$0.isUsedUp && (0...7).contains($0.daysLeft ?? 99) }.count
        let content = UNMutableNotificationContent()
        content.title = "Plan the week?"
        content.body = soon > 0 ? "\(soon) thing\(soon == 1 ? "" : "s") in your kitchen expire this week. Garde can plan dinners around them."
                                : "Garde can plan this week's dinners from what you have."
        content.sound = .default
        var when = DateComponents(); when.weekday = 1; when.hour = 17
        center.add(UNNotificationRequest(identifier: "weekly-plan", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true)))
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
    var mood: String?
    var openWeekPlan = false          // e.g. from the spice rack: "Something that shows off smoked paprika"

    func install() { UNUserNotificationCenter.current().delegate = self }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let name = response.notification.request.content.userInfo["mustUse"] as? String
        let weekly = response.notification.request.identifier == "weekly-plan"
        await MainActor.run {
            if weekly { self.tab = 2; self.openWeekPlan = true; return }
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
