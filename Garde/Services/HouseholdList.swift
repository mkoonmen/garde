import Foundation
import EventKit
import SwiftData

/// Household shopping list through Apple Reminders.
/// Garde keeps a Reminders list called "Garde groceries" in step with the List tab, both ways.
/// Share that list with your household in the Reminders app and everyone can add and tick off items,
/// on any iPhone, without needing Garde.
@MainActor @Observable
final class HouseholdList {
    static let shared = HouseholdList()
    static let listName = "Garde groceries"

    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    var enabled: Bool { UserDefaults.standard.bool(forKey: "household.enabled") }
    var status = ""
    var lastSync: Date?

    /// item id -> reminder id
    private var links: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "household.links") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "household.links") }
    }

    func turnOn(context: ModelContext) async {
        do {
            guard try await store.requestFullAccessToReminders() else {
                status = "Garde needs Reminders access. Turn it on in Settings → Privacy → Reminders."; return
            }
            UserDefaults.standard.set(true, forKey: "household.enabled")
            await sync(context: context)
            watch(context: context)
        } catch { status = "Couldn't open Reminders: \(error.localizedDescription)" }
    }

    func turnOff() {
        UserDefaults.standard.set(false, forKey: "household.enabled")
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        status = "Off. The Reminders list stays; delete it in Reminders if you don't want it."
    }

    /// Re-sync whenever someone changes the shared list.
    func watch(context: ModelContext) {
        guard enabled, observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            Task { @MainActor in await HouseholdList.shared.sync(context: context) }
        }
    }

    private func calendar() throws -> EKCalendar {
        if let c = store.calendars(for: .reminder).first(where: { $0.title == Self.listName }) { return c }
        let c = EKCalendar(for: .reminder, eventStore: store)
        c.title = Self.listName
        c.cgColor = CGColor(red: 0.72, green: 0.45, blue: 0.2, alpha: 1)
        c.source = store.defaultCalendarForNewReminders()?.source
            ?? store.sources.first { $0.sourceType == .calDAV } ?? store.sources.first { $0.sourceType == .local }
        try store.saveCalendar(c, commit: true)
        return c
    }

    /// Two-way merge. Reminders wins for ticks made by someone else; Garde wins for items it created.
    private var syncing = false
    func sync(context: ModelContext) async {
        guard !syncing else { return }
        syncing = true; defer { syncing = false }
        guard enabled, EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return }
        do {
            let cal = try calendar()
            let reminders = await fetchReminders(in: cal)
            let byID = Dictionary(reminders.map { ($0.calendarItemIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
            let items = try context.fetch(FetchDescriptor<ShoppingItem>()).filter { !$0.isDismissed }
            let itemsByID = Dictionary(items.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { a, _ in a })
            var links = self.links
            var linkedReminders = Set(links.values)

            // 1. Items that exist in Garde.
            for item in items {
                let key = item.id.uuidString
                if let rid = links[key], let r = byID[rid] {
                    if r.isCompleted != item.isChecked {
                        // Whoever changed last wins; Reminders' lastModified tells us when they did.
                        if (r.lastModifiedDate ?? .distantPast) > lastSyncDate { item.isChecked = r.isCompleted }
                        else { r.isCompleted = item.isChecked; try store.save(r, commit: false) }
                    }
                } else if links[key] != nil {
                    // Someone deleted it from Reminders: drop it here too.
                    links[key] = nil
                    if !item.isChecked { item.isDismissed = true }
                } else if !item.isChecked {
                    let r = EKReminder(eventStore: store)
                    r.calendar = cal
                    r.title = item.name
                    r.notes = [item.quantityNote, item.reason].filter { !$0.isEmpty }.joined(separator: " · ")
                    try store.save(r, commit: false)
                    links[key] = r.calendarItemIdentifier
                    linkedReminders.insert(r.calendarItemIdentifier)
                }
            }
            // 2. Items removed from Garde: remove their reminders.
            for (key, rid) in links where itemsByID[key] == nil {
                if let r = byID[rid] { try store.remove(r, commit: false) }
                links[key] = nil
            }
            // 3. New reminders someone else added.
            for r in reminders where !linkedReminders.contains(r.calendarItemIdentifier) && !r.isCompleted {
                let name = (r.title ?? "").trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { continue }
                let item = ShoppingItem(name: name, category: ShoppingBrain.guessCategory(name), reason: "Added in Reminders")
                context.insert(item)
                links[item.id.uuidString] = r.calendarItemIdentifier
            }
            try store.commit()
            try context.save()
            self.links = links
            lastSync = .now
            UserDefaults.standard.set(Date.now, forKey: "household.lastSync")
            status = "In step with “\(Self.listName)” in Reminders."
        } catch {
            status = "Reminders sync hit a snag: \(error.localizedDescription)"
        }
    }

    private var lastSyncDate: Date { UserDefaults.standard.object(forKey: "household.lastSync") as? Date ?? .distantPast }

    private func fetchReminders(in cal: EKCalendar) async -> [EKReminder] {
        let pred = store.predicateForReminders(in: [cal])
        return await withCheckedContinuation { cont in
            store.fetchReminders(matching: pred) { r in cont.resume(returning: r ?? []) }
        }
    }
}
