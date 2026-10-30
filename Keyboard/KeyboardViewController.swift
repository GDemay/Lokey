import KeyboardUI
import LlamaRuntime
import SwiftUI
import UIKit
import WritingCore

/// The custom keyboard. Inference runs in this process: the model file is memory-mapped
/// from the App Group container (weights don't count toward the extension's memory limit)
/// and llama.cpp runs CPU-only with small buffers (see LlamaGenerator.Configuration.keyboard).
final class KeyboardViewController: UIInputViewController, KeyboardHost {
    private var controller: KeyboardController!
    private var hosting: UIHostingController<KeyboardView>!
    private let settingsStore = SettingsStore.shared()

    override func viewDidLoad() {
        super.viewDidLoad()
        let document = ProxyDocument(owner: self)
        let store = settingsStore
        controller = KeyboardController(document: document, host: self, settings: store.load()) { [weak self] in
            let (assistant, model) = try await KeyboardEngine.shared.assistant(settings: store.load())
            self?.reportStatus(modelName: model.name)
            return assistant
        }
        hosting = UIHostingController(rootView: KeyboardView(controller: controller))
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(hosting)
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hosting.didMove(toParent: self)
        let height = view.heightAnchor.constraint(equalToConstant: KeyboardView.preferredHeight)
        height.priority = UILayoutPriority.defaultHigh
        height.isActive = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        controller.settings = settingsStore.load()
        controller.resetTransientState()
        reportStatus(modelName: nil)
        let preload = hasFullAccess && controller.settings.autocorrectMode != .off
        Diagnostics.log("keyboard will appear (full access: \(hasFullAccess), preload: \(preload)); \(MemoryBudget.summary())")
        if preload {
            controller.prepareEngine()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        controller.resetTransientState()
        reportStatus(modelName: nil)
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        controller?.textDidChange()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        Diagnostics.log("keyboard memory warning; " + MemoryBudget.summary())
        reportStatus(modelName: nil)
        controller.releaseEngine()
        KeyboardEngine.shared.release()
    }

    private func reportStatus(modelName: String?) {
        guard hasFullAccess else { return }
        var status = settingsStore.loadKeyboardStatus() ?? KeyboardStatus(lastSeen: Date(), hasFullAccess: true)
        status.lastSeen = Date()
        status.hasFullAccess = true
        if let modelName { status.modelName = modelName }
        status.footprintMB = MemoryBudget.footprintBytes().map { Double($0) / 1_048_576 }
        status.peakFootprintMB = MemoryBudget.peakFootprintBytes().map { Double($0) / 1_048_576 }
        settingsStore.saveKeyboardStatus(status)
    }

    // MARK: KeyboardHost

    var returnKeyTitle: String {
        switch textDocumentProxy.returnKeyType ?? .default {
        case .go: return "go"
        case .google, .search, .yahoo: return "search"
        case .join: return "join"
        case .next: return "next"
        case .route: return "route"
        case .send: return "send"
        case .done: return "done"
        case .continue: return "continue"
        default: return "return"
        }
    }

    var autocapitalizesSentences: Bool {
        switch textDocumentProxy.autocapitalizationType {
        case .some(.none): return false
        default: return true
        }
    }

    func playInputClick() {
        UIDevice.current.playInputClick()
    }

    func didFinishModelRequest() {
        reportStatus(modelName: nil)
    }
}

/// Keeps the model loaded across keyboard appearances while the extension process lives.
@MainActor
final class KeyboardEngine {
    static let shared = KeyboardEngine()
    private var cached: (id: String, assistant: WritingAssistant, model: ModelInfo)?
    private var inFlight: (id: String, task: Task<(WritingAssistant, ModelInfo), Error>)?

    func assistant(settings: AppSettings) async throws -> (WritingAssistant, ModelInfo) {
        let catalog = try ModelCatalog.bundled()
        let key = settings.selectedModelID ?? catalog.defaultModelID
        if let cached, cached.id == key { return (cached.assistant, cached.model) }
        if let inFlight, inFlight.id == key { return try await inFlight.task.value }
        // Never hold two models at once in the keyboard's memory budget.
        cached = nil
        let library = try PromptLibrary.bundled()
        let store = ModelStore.shared()
        let task = Task.detached(priority: .userInitiated) {
            try AssistantFactory.make(context: .keyboard, settings: settings, catalog: catalog, store: store, library: library)
        }
        inFlight = (key, task)
        do {
            let (assistant, model) = try await task.value
            if inFlight?.id == key { inFlight = nil }
            cached = (key, assistant, model)
            return (assistant, model)
        } catch {
            if inFlight?.id == key { inFlight = nil }
            throw error
        }
    }

    func release() {
        cached = nil
        inFlight = nil
    }
}

/// Bridges `UITextDocumentProxy` to the keyboard's `TextDocument`.
final class ProxyDocument: TextDocument {
    private weak var owner: UIInputViewController?

    init(owner: UIInputViewController) { self.owner = owner }

    private var proxy: UITextDocumentProxy? { owner?.textDocumentProxy }
    var documentContextBeforeInput: String? { proxy?.documentContextBeforeInput }
    var documentContextAfterInput: String? { proxy?.documentContextAfterInput }
    var selectedText: String? { proxy?.selectedText }
    func insertText(_ text: String) { proxy?.insertText(text) }
    func deleteBackward() { proxy?.deleteBackward() }
    func adjustTextPosition(byCharacterOffset offset: Int) { proxy?.adjustTextPosition(byCharacterOffset: offset) }
}
