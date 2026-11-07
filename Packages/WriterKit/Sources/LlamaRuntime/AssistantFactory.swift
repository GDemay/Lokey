import Foundation
import WritingCore

/// Chooses a model and builds a `WritingAssistant` for the app or the keyboard extension.
public enum AssistantFactory {
    public enum Context: Sendable { case app, keyboard }

    public struct Selection: Sendable {
        public var model: ModelInfo
        public var url: URL
    }

    /// The selected model if it is installed, otherwise the best installed (or bundled) one.
    public static func selection(settings: AppSettings, catalog: ModelCatalog, store: ModelStore,
                                 bundle: Bundle = .main) -> Selection? {
        func locate(_ model: ModelInfo) -> URL? {
            if store.isInstalled(model) { return store.url(for: model) }
            let name = (model.file as NSString).deletingPathExtension
            return bundle.url(forResource: name, withExtension: "gguf")
        }
        let preferred = settings.selectedModelID.flatMap(catalog.model(id:)) ?? catalog.defaultModel
        if let url = locate(preferred) { return Selection(model: preferred, url: url) }
        let order: [ModelInfo.Tier] = [.balanced, .fast, .tiny, .large]
        for tier in order {
            for model in catalog.models where model.tier == tier {
                if let url = locate(model) { return Selection(model: model, url: url) }
            }
        }
        return nil
    }

    public static func make(context: Context, settings: AppSettings,
                            catalog: ModelCatalog, store: ModelStore,
                            library: PromptLibrary, bundle: Bundle = .main) throws -> (WritingAssistant, ModelInfo) {
        guard var selection = selection(settings: settings, catalog: catalog, store: store, bundle: bundle) else {
            if context == .keyboard { throw GeneratorError.noKeyboardModel }
            throw GeneratorError.unavailable("No model downloaded yet. Download one in Models.")
        }
        if context == .keyboard, let available = MemoryBudget.availableBytes() {
            let margin: UInt64 = 10 << 20
            if available < MemoryBudget.estimatedKeyboardCost(for: selection.model) + margin {
                // Fall back to a smaller installed model that fits.
                let smaller = catalog.models
                    .filter { MemoryBudget.estimatedKeyboardCost(for: $0) + margin <= available && store.isInstalled($0) }
                    .min { MemoryBudget.estimatedKeyboardCost(for: $0) < MemoryBudget.estimatedKeyboardCost(for: $1) }
                guard let smaller else {
                    throw GeneratorError.unavailable("Not enough memory for on-device AI in the keyboard right now.")
                }
                selection = Selection(model: smaller, url: store.url(for: smaller))
            }
        }
        var config: LlamaGenerator.Configuration = context == .keyboard ? .keyboard : .app
        // Only bring up Metal (device + shader compile) when the GPU will actually be used.
        // The choice is per process: switching the GPU setting on applies after a relaunch.
        config.allowsMetal = context == .app && settings.useGPU
        if config.allowsMetal { config.gpuLayers = 999 }
        let generator = try LlamaGenerator(modelPath: selection.url.path, format: selection.model.format, configuration: config)
        let assistant = WritingAssistant(library: library, generator: generator)
        if context == .keyboard { assistant.maxInputCharacters = 2_000 }
        return (assistant, selection.model)
    }
}
