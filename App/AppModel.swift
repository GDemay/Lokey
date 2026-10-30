import CryptoKit
import Foundation
import LlamaRuntime
import SwiftUI
import UIKit
import WritingCore

/// App-wide state: models, downloads, settings, and the in-app writing engine.
@MainActor
final class AppModel: ObservableObject {
    enum DownloadState: Equatable {
        case downloading(Double)
        case verifying
        case failed(String)
    }

    let catalog: ModelCatalog
    let library: PromptLibrary
    let store = ModelStore.shared()
    private let settingsStore = SettingsStore.shared()
    private let downloader = ModelDownloader()

    @Published var settings: AppSettings { didSet { settingsStore.save(settings) } }
    @Published private(set) var installed: Set<String> = []
    @Published private(set) var downloads: [String: DownloadState] = [:]
    @Published private(set) var keyboardStatus: KeyboardStatus?
    @Published private(set) var keyboardEnabled = false

    private var engine: (id: String, assistant: WritingAssistant)?

    init() {
        catalog = try! ModelCatalog.bundled()
        library = try! PromptLibrary.bundled()
        var loaded = SettingsStore.shared().load()
        if ProcessInfo.processInfo.arguments.contains("--uitest") {
            loaded.hasCompletedOnboarding = true
            loaded.showChangesBeforeApplying = true
        }
        settings = loaded
        if ProcessInfo.processInfo.arguments.contains("--uitest") { settingsStore.save(loaded) }
        try? store.prepareDirectory()
        refresh()
    }

    var activeModel: ModelInfo? {
        AssistantFactory.selection(settings: settings, catalog: catalog, store: store)?.model
    }

    func refresh() {
        installed = Set(store.installed(in: catalog).map(\.id))
        keyboardStatus = settingsStore.loadKeyboardStatus()
        // iOS lists enabled keyboards (including third-party ones) under this key.
        let enabled = UserDefaults.standard.object(forKey: "AppleKeyboards") as? [String] ?? []
        keyboardEnabled = enabled.contains(Brand.keyboardBundleID)
    }

    // MARK: Engine

    func assistant() async throws -> WritingAssistant {
        guard let model = activeModel else {
            throw GeneratorError.unavailable("No model downloaded yet. Download one in Models.")
        }
        let key = model.id + (settings.useGPU ? "+gpu" : "")
        if let engine, engine.id == key { return engine.assistant }
        engine = nil
        let settings = self.settings, catalog = self.catalog, store = self.store, library = self.library
        let (assistant, _) = try await Task.detached(priority: .userInitiated) {
            try AssistantFactory.make(context: .app, settings: settings, catalog: catalog, store: store, library: library)
        }.value
        engine = (key, assistant)
        return assistant
    }

    func select(_ model: ModelInfo) {
        settings.selectedModelID = model.id
        engine = nil
    }

    // MARK: Downloads

    func download(_ model: ModelInfo) {
        guard downloads[model.id] == nil else { return }
        downloads[model.id] = .downloading(0)
        UIApplication.shared.isIdleTimerDisabled = true
        downloader.start(model, destination: store.url(for: model), store: store) { [weak self] event in
            Task { @MainActor in self?.handle(event, for: model) }
        }
    }

    func cancelDownload(_ model: ModelInfo) {
        downloader.cancel(model)
        downloads[model.id] = nil
        updateIdleTimer()
    }

    func delete(_ model: ModelInfo) {
        try? store.delete(model)
        if engine?.id.hasPrefix(model.id) == true { engine = nil }
        refresh()
    }

    private func handle(_ event: ModelDownloader.Event, for model: ModelInfo) {
        // Progress callbacks are queued many times per second; drop the ones that arrive after
        // the user cancelled or the download moved on, so they can't resurrect the row.
        let current = downloads[model.id]
        switch event {
        case .progress(let p):
            guard case .downloading? = current else { return }
            downloads[model.id] = .downloading(p)
        case .verifying:
            guard current != nil else { return }
            downloads[model.id] = .verifying
        case .finished:
            downloads[model.id] = nil
            if current != nil, settings.selectedModelID == nil { settings.selectedModelID = model.id }
            refresh()
        case .failed(let message):
            guard current != nil else { return }
            downloads[model.id] = .failed(message)
        }
        updateIdleTimer()
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = downloads.values.contains {
            if case .failed = $0 { return false } else { return true }
        }
    }
}

/// Downloads GGUF files with progress, verifies their SHA-256 against the catalog, then moves them into place.
final class ModelDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    enum Event { case progress(Double), verifying, finished, failed(String) }

    private struct Job {
        let model: ModelInfo
        let destination: URL
        let store: ModelStore
        let onEvent: (Event) -> Void
    }

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 60 * 60 * 3
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    private var jobs: [Int: Job] = [:]
    private let lock = NSLock()

    func start(_ model: ModelInfo, destination: URL, store: ModelStore, onEvent: @escaping (Event) -> Void) {
        let task = session.downloadTask(with: model.url)
        lock.lock(); jobs[task.taskIdentifier] = Job(model: model, destination: destination, store: store, onEvent: onEvent); lock.unlock()
        task.resume()
    }

    func cancel(_ model: ModelInfo) {
        lock.lock()
        let ids = jobs.filter { $0.value.model.id == model.id }.map(\.key)
        ids.forEach { jobs[$0] = nil }
        lock.unlock()
        session.getAllTasks { tasks in tasks.filter { ids.contains($0.taskIdentifier) }.forEach { $0.cancel() } }
    }

    private func job(_ task: URLSessionTask) -> Job? {
        lock.lock(); defer { lock.unlock() }
        return jobs[task.taskIdentifier]
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let job = job(downloadTask) else { return }
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : job.model.sizeBytes
        job.onEvent(.progress(Double(totalBytesWritten) / Double(max(1, total))))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let job = job(downloadTask) else { return }
        job.onEvent(.verifying)
        do {
            if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            // The temporary file is deleted when this method returns: hash it, then move it.
            let digest = try Self.sha256(of: location)
            guard digest == job.model.sha256 else { throw DownloadError.checksumMismatch }
            try job.store.prepareDirectory()
            if FileManager.default.fileExists(atPath: job.destination.path) {
                try FileManager.default.removeItem(at: job.destination)
            }
            try FileManager.default.moveItem(at: location, to: job.destination)
            job.onEvent(.finished)
        } catch {
            job.onEvent(.failed(error.localizedDescription))
        }
        lock.lock(); jobs[downloadTask.taskIdentifier] = nil; lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let job = job(task) else { return }
        if (error as? URLError)?.code != .cancelled { job.onEvent(.failed(error.localizedDescription)) }
        lock.lock(); jobs[task.taskIdentifier] = nil; lock.unlock()
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    enum DownloadError: LocalizedError {
        case checksumMismatch
        var errorDescription: String? { "The download was corrupted (checksum mismatch). Please try again." }
    }
}
