import Foundation
import SwiftData
import CoreData
import AppKit
import CloudKit

let app = NSApplication.shared
let diagnosticLog = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("garde-schema-output.log")
freopen(diagnosticLog.path, "w", stdout)
freopen(diagnosticLog.path, "a", stderr)

let types: [any PersistentModel.Type] = [PantryItem.self, Receipt.self, Spice.self, SavedRecipe.self, KitchenProfile.self, ShoppingItem.self, MealPlanEntry.self, CookLog.self, BarBottle.self, TakeoutOrder.self, KitchenEvent.self]
let model = NSManagedObjectModel.makeManagedObjectModel(for: types)!
let container = NSPersistentCloudKitContainer(name: "GardeSchemaReview", managedObjectModel: model)
let store = NSPersistentStoreDescription(url: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("garde-schema-review.sqlite"))
store.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: GardeStore.cloudContainer)
store.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
store.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
container.persistentStoreDescriptions = [store]
let observer = NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: container, queue: nil) { note in
    if let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event {
        print("CLOUD EVENT: \(event.type.rawValue), ended=\(String(describing: event.endDate)), success=\(event.succeeded), error=\(String(describing: event.error))")
        fflush(stdout)
    }
}
container.loadPersistentStores { _, error in
    if let error { print("STORE ERROR: \(error)"); exit(1) }
    CKContainer(identifier: GardeStore.cloudContainer).accountStatus { status, error in
        print("ACCOUNT STATUS: \(status.rawValue), \(String(describing: error))")
        fflush(stdout)
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
            do { try container.initializeCloudKitSchema(options: CommandLine.arguments.contains("--initialize") ? [.printSchema] : [.dryRun, .printSchema]); print("SCHEMA VALID") }
            catch { print("SCHEMA ERROR: \(error)") }
            exit(0)
        }
    }
}
RunLoop.main.run()
