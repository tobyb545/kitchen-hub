import Foundation

/// Hand-off folder in the App Group shared by the app and its Share extension.
///
/// The Share extension can't import recipes itself (it only lives for a few seconds and has a
/// tight memory limit), so it drops what it was given here and the app picks it up the next
/// time it's active, or straight away if it's on screen (via a Darwin notification).
enum ImportInbox {
    static let appGroup = "group.com.tobyblunt.kitchenhub"
    static let notificationName = "com.tobyblunt.kitchenhub.inbox-changed"

    struct Item: Codable, Identifiable {
        enum Kind: String, Codable { case link, text, files }
        var id = UUID()
        var kind: Kind
        var text: String = ""
        /// File names inside the inbox folder (photos, PDFs, text files).
        var files: [String] = []
        var created = Date()
    }

    static var folder: URL? {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return nil }
        let dir = base.appendingPathComponent("Inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    enum InboxError: LocalizedError {
        case unavailable
        var errorDescription: String? { "Kitchen Hub's shared folder isn't available. Open Kitchen Hub once, then try again." }
    }

    static func save(_ item: Item) throws {
        guard let folder else { throw InboxError.unavailable }
        let data = try JSONEncoder().encode(item)
        try data.write(to: folder.appendingPathComponent("\(item.id.uuidString).json"), options: .atomic)
        notify()
    }

    /// Stores raw file data and returns its name in the inbox.
    static func storeFile(data: Data, ext: String) throws -> String {
        guard let folder else { throw InboxError.unavailable }
        let name = "\(UUID().uuidString).\(ext.isEmpty ? "bin" : ext)"
        try data.write(to: folder.appendingPathComponent(name), options: .atomic)
        return name
    }

    static func storeFile(copying url: URL) throws -> String {
        guard let folder else { throw InboxError.unavailable }
        let name = "\(UUID().uuidString).\(url.pathExtension.isEmpty ? "bin" : url.pathExtension.lowercased())"
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try FileManager.default.copyItem(at: url, to: folder.appendingPathComponent(name))
        return name
    }

    static func url(forFile name: String) -> URL? {
        guard let folder else { return nil }
        let url = folder.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func pending() -> [Item] {
        guard let folder,
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        return names.filter { $0.hasSuffix(".json") }
            .compactMap { try? Data(contentsOf: folder.appendingPathComponent($0)) }
            .compactMap { try? JSONDecoder().decode(Item.self, from: $0) }
            .sorted { $0.created < $1.created }
    }

    static func remove(_ item: Item) {
        guard let folder else { return }
        for name in item.files { try? FileManager.default.removeItem(at: folder.appendingPathComponent(name)) }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(item.id.uuidString).json"))
    }

    static func notify() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(notificationName as CFString), nil, nil, true)
    }
}
