import Foundation

public struct CorrectionHistory: Sendable {
    public struct Item: Identifiable, Sendable {
        public let correction: CorrectionExample
        public var count: Int
        public var lastSeen: Date
        public var id: CorrectionExample { correction }
    }

    private struct Event: Codable {
        let date: Date
        let corrections: [CorrectionExample]
    }

    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func shared() -> CorrectionHistory? {
        #if os(iOS) || os(macOS)
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Brand.appGroupID)
            .map { CorrectionHistory(directory: $0.appendingPathComponent("CorrectionHistory", isDirectory: true)) }
        #else
        nil
        #endif
    }

    public func record(id: UUID, date: Date, original: String, corrected: String, languageHint: String? = nil) throws {
        let corrections = CorrectionExample.extract(from: original, corrected: corrected, languageHint: languageHint)
        guard !corrections.isEmpty else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let event = Event(date: date, corrections: corrections)
        let data = try JSONEncoder().encode(event)
        #if os(iOS)
        var folder = directory
        var resources = URLResourceValues()
        resources.isExcludedFromBackup = true
        try folder.setResourceValues(resources)
        try data.write(to: eventURL(id), options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: eventURL(id), options: .atomic)
        #endif
    }

    public func remove(_ id: UUID) throws {
        try removeFile(eventURL(id))
    }

    public func clear() throws {
        for file in try eventFiles() { try removeFile(file) }
    }

    public func items() throws -> [Item] {
        let decoder = JSONDecoder()
        var groups: [CorrectionExample: Item] = [:]
        for file in try eventFiles() {
            // The keyboard may undo a correction while the app is opening the history.
            guard let data = try? Data(contentsOf: file),
                  let event = try? decoder.decode(Event.self, from: data) else { continue }
            for correction in event.corrections {
                var item = groups[correction] ?? Item(correction: correction, count: 0, lastSeen: event.date)
                item.count += 1
                item.lastSeen = max(item.lastSeen, event.date)
                groups[correction] = item
            }
        }
        return groups.values.sorted { $0.lastSeen > $1.lastSeen }
    }

    private func eventURL(_ id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }

    private func eventFiles() throws -> [URL] {
        do {
            return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil }
        } catch CocoaError.fileReadNoSuchFile {
            return []
        }
    }

    private func removeFile(_ file: URL) throws {
        do {
            try FileManager.default.removeItem(at: file)
        } catch CocoaError.fileNoSuchFile {
            // An Undo and Clear History can remove the same event.
        }
    }
}
