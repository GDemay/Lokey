import Foundation

public struct ModelInfo: Codable, Identifiable, Hashable, Sendable {
    public enum Tier: String, Codable, Sendable { case tiny, fast, balanced, large }

    public var id: String
    public var name: String
    public var family: String
    public var parameters: String
    /// Key into `PromptLibrary.formats`.
    public var format: String
    public var file: String
    public var url: URL
    public var sizeBytes: Int64
    public var sha256: String
    public var license: String
    public var licenseURL: URL
    public var tier: Tier
    public var summary: String

    public var sizeDescription: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

public struct ModelCatalog: Codable, Sendable {
    public var version: Int
    public var defaultModelID: String
    public var models: [ModelInfo]

    public static func bundled() throws -> ModelCatalog {
        guard let url = Bundle.module.url(forResource: "models", withExtension: "json") else {
            throw PromptError.missingResource("models.json")
        }
        return try JSONDecoder().decode(ModelCatalog.self, from: Data(contentsOf: url))
    }

    public func model(id: String) -> ModelInfo? { models.first { $0.id == id } }

    public var defaultModel: ModelInfo { model(id: defaultModelID) ?? models[0] }
}

/// Where downloaded models live. On iOS this is the App Group container so the keyboard
/// extension can memory-map the same file the app downloaded.
public struct ModelStore: Sendable {
    public let directory: URL
    public let isSharedContainer: Bool

    public init(directory: URL, isSharedContainer: Bool = false) {
        self.directory = directory
        self.isSharedContainer = isSharedContainer
    }

    public static func shared(appGroupID: String = Brand.appGroupID) -> ModelStore {
        #if canImport(Darwin)
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return ModelStore(directory: container.appendingPathComponent("Models", isDirectory: true), isSharedContainer: true)
        }
        #endif
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return ModelStore(directory: base.appendingPathComponent("Models", isDirectory: true))
    }

    public func url(for model: ModelInfo) -> URL {
        directory.appendingPathComponent(model.file)
    }

    public func isInstalled(_ model: ModelInfo) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url(for: model).path),
              let size = attrs[.size] as? NSNumber else { return false }
        return size.int64Value == model.sizeBytes
    }

    public func installed(in catalog: ModelCatalog) -> [ModelInfo] {
        catalog.models.filter(isInstalled)
    }

    public func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func delete(_ model: ModelInfo) throws {
        let path = url(for: model)
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
    }
}
