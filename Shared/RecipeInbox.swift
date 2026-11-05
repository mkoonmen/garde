import Foundation

/// Things shared to Garde from other apps (Safari, TikTok, Instagram, Photos…) wait here until the app opens.
/// Plain JSON in the App Group folder, so the share extension and the app both read it.
struct InboxItem: Codable, Identifiable {
    var id = UUID()
    var url: String?
    var text: String?
    var imageFile: String?      // file name inside the inbox folder
    var received = Date()
}

enum RecipeInbox {
    static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GardeStore.appGroup)?
            .appendingPathComponent("Inbox", isDirectory: true)
    }
    static var listFile: URL? { folder?.appendingPathComponent("inbox.json") }

    static func load() -> [InboxItem] {
        guard let f = listFile, let data = try? Data(contentsOf: f) else { return [] }
        return (try? JSONDecoder().decode([InboxItem].self, from: data)) ?? []
    }

    static func save(_ items: [InboxItem]) {
        guard let folder, let f = listFile else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? JSONEncoder().encode(items).write(to: f, options: .atomic)
    }

    static func add(url: String? = nil, text: String? = nil, imageData: Data? = nil) {
        var item = InboxItem(url: url, text: text)
        if let imageData, let folder {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let name = item.id.uuidString + ".jpg"
            try? imageData.write(to: folder.appendingPathComponent(name))
            item.imageFile = name
        }
        save(load() + [item])
    }

    static func remove(_ id: UUID) {
        var all = load()
        if let item = all.first(where: { $0.id == id }), let file = item.imageFile, let folder {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
        }
        all.removeAll { $0.id == id }
        save(all)
    }

    static func imageData(for item: InboxItem) -> Data? {
        guard let file = item.imageFile, let folder else { return nil }
        return try? Data(contentsOf: folder.appendingPathComponent(file))
    }
}
