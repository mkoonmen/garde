# Garde CloudKit schema

The 3.0 schema was generated from all eleven SwiftData models using Apple's `NSManagedObjectModel.makeManagedObjectModel` and `NSPersistentCloudKitContainer.initializeCloudKitSchema`. The exported `schema-3.0.ckdb` contains schema definitions only. No kitchen records are in this file.

On November 6, 2026, both development and production originally contained only the built-in Users record type. The generated application types and indexes were initialized in development and deployed to production in CloudKit Console. The console confirmed “The schema is deployed to Production.”

The small macOS diagnostic target is separate from the iPhone app and uses a temporary SQLite store. Its default mode validates without uploading records. Passing `--initialize` asks Apple's initializer to upload and remove representative development records to create all fields. It never opens the iPhone's App Group store. A signed development profile with this container is required.

`main.swift` logs its result to `garde-schema-output.log` in the process's temporary directory. Successful validation ends with `SCHEMA VALID`. Build the target from this folder's project.yml using xcodegen and Xcode. The generated Xcode project and build products are disposable.

After any future model change, initialize the development schema, review its diff in CloudKit Console, export a fresh schema snapshot, and deploy additions before distributing the new TestFlight build. Production schema deployment does not copy development kitchen data. Actual sync between two physical devices still requires a separate check.
