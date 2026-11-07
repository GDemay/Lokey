#if canImport(UIKit)
import Foundation
import SwiftUI
import UIKit
import WritingCore

/// What the keyboard needs from its host (the extension's UIInputViewController, or the in-app preview).
@MainActor
public protocol KeyboardHost: AnyObject {
    var hasFullAccess: Bool { get }
    var needsInputModeSwitchKey: Bool { get }
    var returnKeyTitle: String { get }
    var autocapitalizesSentences: Bool { get }
    var localModelName: String? { get }
    var selectedLocalModelName: String? { get }
    var appleFixUnavailableReason: String? { get }
    func advanceToNextInputMode()
    func playInputClick()
    func recordCorrection(original: String, corrected: String, languageHint: String?) -> UUID?
    func removeCorrection(_ id: UUID)
    /// Called after each model request, e.g. to record the process's peak memory.
    func didFinishModelRequest()
}

public extension KeyboardHost {
    var localModelName: String? { nil }
    var selectedLocalModelName: String? { nil }
    var appleFixUnavailableReason: String? { nil }
    func recordCorrection(original: String, corrected: String, languageHint: String?) -> UUID? { nil }
    func removeCorrection(_ id: UUID) {}
    func didFinishModelRequest() {}
}

/// Lazily provides the writing assistant (loads the model on first use).
public typealias AssistantProvider = @MainActor () async throws -> WritingAssistant

/// The keyboard's brain: typing behaviour, AI actions, autocorrect-as-you-type and undo.
@MainActor
public final class KeyboardController: ObservableObject {
    public enum Layer: Equatable { case letters, numbers, symbols }
    public enum Shift: Equatable { case off, once, locked }
    public enum Panel: Equatable { case keys, enhance, translate, emoji, models }

    public enum Phase: Equatable {
        case idle
        case working(action: WritingAction, partial: String)
        case result(action: WritingAction, result: AssistantResult)
        case message(String)
    }

    /// Feedback for a correction made while typing.
    public struct LiveNotice: Equatable {
        public enum Kind: Equatable { case applied, suggested }
        public var kind: Kind
        public var pending: PendingCorrection
        public var corrected: String
        public var summary: String
        var historyID: UUID?
    }

    public enum EngineStatus: Equatable {
        case idle, loading, ready, unavailable(String)
    }

    public enum FixFallback: Equatable {
        case preparing
        case localModel(String)
    }

    /// What an action read from the document, so Apply can check nothing moved since.
    private struct Target: Equatable {
        var text: String
        var isSelection: Bool
        var after: String
    }

    @Published public var layer: Layer = .letters
    @Published public var shift: Shift = .once
    @Published public var panel: Panel = .keys
    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var suggestions: [String] = []
    /// Time from tapping an action to its result, including any model loading or queueing.
    @Published public private(set) var lastWaitSeconds: Double?
    @Published public private(set) var fixFallback: FixFallback?
    @Published public private(set) var liveNotice: LiveNotice?
    @Published public private(set) var engineStatus: EngineStatus = .idle
    @Published private var undoRecord: (original: String, replacement: String, historyID: UUID?)?
    @Published public var settings: AppSettings {
        didSet {
            if modelKey(settings) != modelKey(oldValue) { dropEngine() }
        }
    }

    public let document: TextDocument
    public weak var host: KeyboardHost?

    private let assistantProvider: AssistantProvider
    private let appleFixProvider: AssistantProvider
    private var assistant: WritingAssistant?
    /// One in-flight model load shared by every caller (the keyboard can't afford two).
    private var loadTask: Task<WritingAssistant, Error>?
    private var loadGeneration = 0
    private var actionTask: Task<Void, Never>?
    private var liveTask: Task<Void, Never>?
    private var pendingTarget: Target?
    private let livePolicy = LiveCorrectionPolicy()
    /// Sentences the user undid: never auto-correct them again in this session.
    private var declined: Set<String> = []
    private var lastSpaceTime: Date?
    private let textChecker = UITextChecker()
    private var spellingSuggestionLanguage: String?
    private let haptics = UIImpactFeedbackGenerator(style: .light)

    public init(document: TextDocument, host: KeyboardHost?, settings: AppSettings,
                appleFixProvider: @escaping AssistantProvider = {
                    throw GeneratorError.unavailable("Apple Intelligence is unavailable.")
                },
                assistantProvider: @escaping AssistantProvider) {
        self.document = document
        self.host = host
        self.settings = settings
        self.appleFixProvider = appleFixProvider
        self.assistantProvider = assistantProvider
    }

    // MARK: Typing

    public func type(_ text: String) {
        feedback()
        var s = text
        if layer == .letters, shift != .off { s = s.uppercased() }
        document.insertText(s)
        if shift == .once { shift = .off }
        if layer != .letters, text == " " || text == "'" { layer = .letters }
        afterEdit(inserted: s)
    }

    public func insertEmoji(_ emoji: String) {
        feedback()
        document.insertText(emoji)
        afterEdit(inserted: emoji)
    }

    public func space() {
        feedback()
        let before = document.documentContextBeforeInput ?? ""
        if let last = lastSpaceTime, Date().timeIntervalSince(last) < 0.6, before.hasSuffix(" "),
           let prev = before.dropLast().last, prev.isLetter || prev.isNumber {
            document.deleteBackward()
            document.insertText(". ")
            lastSpaceTime = nil
            afterEdit(inserted: ". ")
            return
        }
        let correction = wordCorrection(before: before)
        if let (word, replacement) = correction {
            EditPlanner.apply(EditPlanner.plan(original: word, replacement: replacement + " "), to: document)
        } else {
            document.insertText(" ")
        }
        afterEdit(inserted: " ")
        if let (word, replacement) = correction {
            let historyID = recordCorrection(original: word, corrected: replacement, languageHint: "fr")
            undoRecord = (word + " ", replacement + " ", historyID)
        }
        lastSpaceTime = Date()
        if layer != .letters { layer = .letters }
    }

    public func newline() {
        feedback()
        document.insertText("\n")
        afterEdit(inserted: "\n")
    }

    func moveTypingCursor(by offset: Int) {
        guard offset != 0 else { return }
        let context = offset < 0 ? document.documentContextBeforeInput : document.documentContextAfterInput
        guard let context else { return }
        let crossed = offset < 0 ? context.suffix(-offset) : context.prefix(offset)
        guard !crossed.isEmpty, EditPlanner.isOffsetSafe(String(crossed)) else { return }
        lastSpaceTime = nil
        undoRecord = nil
        document.adjustTextPosition(byCharacterOffset: offset < 0 ? -crossed.count : crossed.count)
    }

    public func backspace() {
        feedback()
        if case .applied = liveNotice?.kind { liveNotice = nil }
        document.deleteBackward()
        undoRecord = nil
        lastSpaceTime = nil
        updateShiftForContext()
        updateSuggestions()
    }

    /// Deletes the previous word (used when the delete key is held).
    public func deleteWord() {
        let before = document.documentContextBeforeInput ?? ""
        let trailingSpaces = before.reversed().prefix(while: { $0 == " " }).count
        let word = before.dropLast(trailingSpaces).reversed().prefix(while: { !$0.isWhitespace }).count
        for _ in 0..<max(1, trailingSpaces + word) { document.deleteBackward() }
        undoRecord = nil
        updateShiftForContext()
        updateSuggestions()
    }

    /// True when there is nothing left to delete before the cursor (stops delete repeat).
    public var isAtStart: Bool {
        guard let before = document.documentContextBeforeInput else { return false }
        return before.isEmpty
    }

    public func toggleShift() {
        switch shift {
        case .off: shift = .once
        case .once, .locked: shift = .off
        }
    }

    public func lockShift() { shift = .locked }

    public func applySuggestion(_ word: String) {
        let current = Self.currentWord(in: document.documentContextBeforeInput ?? "")
        let language = spellingSuggestionLanguage
        for _ in 0..<current.count { document.deleteBackward() }
        document.insertText(word + " ")
        if let language, current != word {
            _ = recordCorrection(original: current, corrected: word, languageHint: language)
        }
        afterEdit(inserted: " ")
    }

    private func afterEdit(inserted: String) {
        undoRecord = nil
        if case .result = phase { phase = .idle }
        if case .message = phase { phase = .idle }
        if inserted != " " { lastSpaceTime = nil }
        updateShiftForContext()
        updateSuggestions()
        if inserted.last == " " || inserted.last == "\n" { scheduleLiveCorrection() }
    }

    func refreshAfterExternalChange() {
        updateShiftForContext()
        updateSuggestions()
    }

    /// Clears per-field state (results, notices, undo, pending work). Call when the keyboard
    /// appears, disappears or moves to another text field.
    public func resetTransientState() {
        actionTask?.cancel()
        liveTask?.cancel()
        phase = .idle
        fixFallback = nil
        panel = .keys
        liveNotice = nil
        undoRecord = nil
        pendingTarget = nil
        lastSpaceTime = nil
        layer = .letters
        shift = .once
        // A model may have been downloaded since the last failure: allow a new attempt.
        if case .unavailable = engineStatus { engineStatus = .idle }
        refreshAfterExternalChange()
    }

    private func updateShiftForContext() {
        guard shift != .locked, layer == .letters else { return }
        if host?.autocapitalizesSentences == false {
            if shift == .once { shift = .off }
            return
        }
        // Some hosts never report context; don't re-arm shift on every key there.
        guard let before = document.documentContextBeforeInput else { return }
        let trimmed = before.trimmingCharacters(in: .whitespaces)
        if before.isEmpty || before.hasSuffix("\n") {
            shift = .once
        } else if before.hasSuffix(" "), let last = trimmed.last, TextChunker.sentenceTerminators.contains(last) {
            shift = .once
        } else if shift == .once {
            shift = .off
        }
    }

    // MARK: Spelling suggestions

    static func currentWord(in before: String) -> String {
        String(before.reversed().prefix(while: { $0.isLetter || $0 == "'" || $0 == "’" }).reversed())
    }

    private func wordCorrection(before: String) -> (word: String, replacement: String)? {
        guard settings.autocorrectMode == .automatic, settings.keyboardLayout.resolved() == .azerty,
              document.selectedText?.isEmpty != false else { return nil }
        let after = document.documentContextAfterInput
        guard after?.first.map(\.isWhitespace) != false else { return nil }
        let word = Self.currentWord(in: before)
        let prefix = before.dropLast(word.count)
        guard (4...24).contains(word.count), word.allSatisfy(\.isLetter),
              word.dropFirst().allSatisfy(\.isLowercase),
              prefix.last?.isWhitespace != false else { return nil }
        if word.first?.isUppercase == true {
            let previous = prefix.reversed().drop(while: { $0.isWhitespace && !$0.isNewline }).first
            if let previous, !previous.isNewline, !TextChunker.sentenceTerminators.contains(previous) {
                return nil
            }
        }
        let range = NSRange(location: 0, length: word.utf16.count)
        guard let guesses = spellingGuesses(for: word, range: range, language: "fr_FR"),
              let replacement = AzertyWordCorrection.uniqueMatch(for: word, guesses: guesses),
              textChecker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0,
                                               wrap: false, language: "en_US").location != NSNotFound,
              document.documentContextBeforeInput == before, document.documentContextAfterInput == after,
              document.selectedText?.isEmpty != false else { return nil }
        return (word, replacement)
    }

    private func spellingGuesses(for word: String, range: NSRange, language: String) -> [String]? {
        let misspelled = textChecker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0,
                                                          wrap: false, language: language)
        guard misspelled.location != NSNotFound else { return nil }
        return textChecker.guesses(forWordRange: range, in: word, language: language) ?? []
    }

    private func updateSuggestions() {
        spellingSuggestionLanguage = nil
        guard settings.spellingSuggestions else { suggestions = []; return }
        let word = Self.currentWord(in: document.documentContextBeforeInput ?? "")
        guard word.count >= 2 else { suggestions = []; return }
        let context = String((document.documentContextBeforeInput ?? "").suffix(180))
        let language = CorrectionLanguage.detect(in: context) == .french ? "fr_FR" : "en_US"
        let range = NSRange(location: 0, length: (word as NSString).length)
        var result: [String]
        if let guesses = spellingGuesses(for: word, range: range, language: language) {
            result = guesses
            spellingSuggestionLanguage = language == "fr_FR" ? "fr" : "en"
        } else {
            result = textChecker.completions(forPartialWordRange: range, in: word, language: language) ?? []
            if !result.contains(word) { result.insert(word, at: 0) }
        }
        suggestions = Array(result.prefix(3))
    }

    // MARK: Engine

    private func modelKey(_ settings: AppSettings) -> String {
        (settings.selectedModelID ?? "default") + (settings.useGPU ? "+gpu" : "")
    }

    /// Starts loading the model in the background (e.g. when the keyboard appears).
    public func prepareEngine() {
        guard assistant == nil, loadTask == nil else { return }
        Task { _ = try? await readyAssistant() }
    }

    private func readyAssistant() async throws -> WritingAssistant {
        if let assistant { return assistant }
        if let loadTask { return try await loadTask.value }
        loadGeneration += 1
        let generation = loadGeneration
        engineStatus = .loading
        let provider = assistantProvider
        let task = Task { @MainActor in try await provider() }
        loadTask = task
        do {
            let loaded = try await task.value
            if generation == loadGeneration {
                assistant = loaded
                loadTask = nil
                engineStatus = .ready
                let context = document.documentContextBeforeInput ?? ""
                let french = CorrectionLanguage.detect(in: context) == .french
                    || (context.isEmpty && settings.keyboardLayout.resolved() == .azerty)
                Task { await loaded.prewarm(actionID: french ? "fix_french" : "fix") }
            }
            return loaded
        } catch {
            if generation == loadGeneration {
                loadTask = nil
                engineStatus = .unavailable(error.localizedDescription)
            }
            throw error
        }
    }

    private func dropEngine() {
        loadGeneration += 1
        loadTask = nil
        assistant = nil
        engineStatus = .idle
    }

    /// Releases the model, e.g. on a memory warning.
    public func releaseEngine() {
        actionTask?.cancel()
        liveTask?.cancel()
        if case .working = phase { phase = .message("Stopped to free memory. Try again.") }
        liveNotice = nil
        dropEngine()
    }

    // MARK: AI actions

    /// The text an action works on: the selection, or everything around the cursor.
    private func currentTarget() -> Target {
        if let selected = document.selectedText, !selected.isEmpty {
            return Target(text: selected, isSelection: true, after: "")
        }
        let before = document.documentContextBeforeInput ?? ""
        let after = document.documentContextAfterInput ?? ""
        // Moving the cursor past `after` is only reliable when offsets are unambiguous.
        return EditPlanner.isOffsetSafe(after)
            ? Target(text: before + after, isSelection: false, after: after)
            : Target(text: before, isSelection: false, after: "")
    }

    public func run(_ action: WritingAction) {
        run(action, retryingWithLocalModel: false)
    }

    private func run(_ action: WritingAction, retryingWithLocalModel: Bool) {
        fixFallback = nil
        guard action.id != WritingAction.ask.id else {
            phase = .message("This action is not available.")
            return
        }
        liveTask?.cancel()
        liveNotice = nil
        panel = .keys
        let target = currentTarget()
        guard !target.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            phase = .message("Type something first.")
            return
        }
        phase = .working(action: action, partial: "")
        let started = Date()
        actionTask?.cancel()
        actionTask = Task {
            do {
                let onPartial: @Sendable (String) -> Void = { partial in
                    Task { @MainActor [weak self] in
                        guard let self, case .working(let current, _) = self.phase, current == action else { return }
                        self.phase = .working(action: action, partial: partial)
                    }
                }
                let result = try await runAction(action, target: target, retryingWithLocalModel: retryingWithLocalModel,
                                                 onPartial: onPartial)
                host?.didFinishModelRequest()
                try Task.checkCancellation()
                lastWaitSeconds = Date().timeIntervalSince(started)
                if !result.hasChanges {
                    phase = .message(result.rejectedChunks > 0 ? "No safe suggestion for this text." : "No changes suggested.")
                } else if action == .fix && !settings.showChangesBeforeApplying && fixFallback == nil {
                    apply(result, target: target)
                } else {
                    pendingTarget = target
                    phase = .result(action: action, result: result)
                }
            } catch is CancellationError {
                if !Task.isCancelled, case .working(let current, _) = phase, current == action { phase = .idle }
            } catch {
                guard !Task.isCancelled else { return }
                phase = .message(error.localizedDescription)
            }
        }
    }

    private func runAction(_ action: WritingAction, target: Target, retryingWithLocalModel: Bool,
                           onPartial: @escaping @Sendable (String) -> Void) async throws -> AssistantResult {
        if action == .fix && settings.useAppleIntelligenceForFix {
            if !retryingWithLocalModel {
                do {
                    let apple = try await appleFixProvider()
                    return try await apple.run(actionID: action.id, text: target.text, onPartial: onPartial)
                } catch GeneratorError.appleFixDeclined {
                    try Task.checkCancellation()
                }
            }
            fixFallback = .preparing
            let local: WritingAssistant
            do {
                local = try await readyAssistant()
            } catch GeneratorError.noKeyboardModel {
                try Task.checkCancellation()
                fixFallback = nil
                throw GeneratorError.unavailable("Apple Intelligence couldn’t complete Fix. Download a local model in Lokey to try again.")
            }
            try Task.checkCancellation()
            guard currentTarget() == target else {
                throw GeneratorError.unavailable("The text changed. Run it again.")
            }
            fixFallback = .localModel(host?.localModelName ?? "Local model")
            return try await local.run(actionID: action.id, text: target.text, onPartial: onPartial)
        }
        let local = try await readyAssistant()
        return try await local.run(actionID: action.id, text: target.text, onPartial: onPartial)
    }

    public func applyResult() {
        guard case .result(_, let result) = phase, let target = pendingTarget else { return }
        apply(result, target: target)
    }

    private func apply(_ result: AssistantResult, target: Target) {
        // Refuse to write if the text, the cursor or the selection changed since we read it.
        guard currentTarget() == target, result.original == target.text else {
            phase = .message("The text changed. Run it again.")
            pendingTarget = nil
            return
        }
        if target.isSelection {
            document.insertText(result.output)
        } else {
            if !target.after.isEmpty { document.adjustTextPosition(byCharacterOffset: target.after.count) }
            EditPlanner.apply(EditPlanner.plan(original: result.original, replacement: result.output), to: document)
        }
        let historyID = result.actionID == WritingAction.fix.id
            ? recordCorrection(original: result.original, corrected: result.output) : nil
        undoRecord = target.isSelection ? nil : (result.original, result.output, historyID)
        pendingTarget = nil
        phase = .idle
        notifySuccess()
        updateShiftForContext()
    }

    public var canUndo: Bool { undoRecord != nil }

    public func undo() {
        guard let record = undoRecord else { return }
        undoRecord = nil
        let before = document.documentContextBeforeInput ?? ""
        // Hosts may truncate the context; accept a visible tail of the replacement.
        let intact = before.hasSuffix(record.replacement) || (before.count >= 40 && record.replacement.hasSuffix(before))
        guard intact, document.selectedText?.isEmpty != false else { return }
        EditPlanner.apply(EditPlanner.plan(original: record.replacement, replacement: record.original), to: document)
        if let id = record.historyID { host?.removeCorrection(id) }
        updateShiftForContext()
    }

    public func retry() {
        if case .result(let action, _) = phase { run(action, retryingWithLocalModel: fixFallback != nil) }
    }

    public func dismissPhase() {
        actionTask?.cancel()
        pendingTarget = nil
        fixFallback = nil
        phase = .idle
    }

    func openPanel(_ panel: Panel) {
        dismissPhase()
        self.panel = panel
    }

    // MARK: Autocorrect as you type

    private func scheduleLiveCorrection() {
        guard settings.autocorrectMode != .off, host?.hasFullAccess ?? false, case .idle = phase else { return }
        if case .unavailable = engineStatus { return }
        guard let pending = livePolicy.completedSentence(in: document.documentContextBeforeInput ?? ""),
              !declined.contains(pending.original) else { return }
        liveTask?.cancel()
        liveTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000)  // let a burst of punctuation settle
            guard !Task.isCancelled, let assistant = try? await readyAssistant(),
                  let result = try? await assistant.run(actionID: WritingAction.fix.id, text: pending.original) else { return }
            host?.didFinishModelRequest()
            guard !Task.isCancelled, result.hasChanges, case .idle = phase else { return }
            let corrected = result.output
            // Never offer a fix that can no longer be placed (the sentence was edited meanwhile).
            guard let steps = livePolicy.reconcile(pending, corrected: corrected,
                                                   contextBefore: document.documentContextBeforeInput ?? "") else { return }
            let summary = result.changes.prefix(2).joined(separator: ", ")
            if settings.autocorrectMode == .automatic, result.changeRatio <= settings.automaticMaxChange {
                EditPlanner.apply(steps, to: document)
                let historyID = recordCorrection(original: pending.original, corrected: corrected)
                liveNotice = LiveNotice(kind: .applied, pending: pending, corrected: corrected, summary: summary,
                                        historyID: historyID)
            } else {
                liveNotice = LiveNotice(kind: .suggested, pending: pending, corrected: corrected, summary: summary)
            }
        }
    }

    /// Applies a suggested live correction, or reverts an applied one.
    public func resolveLiveNotice() {
        guard let notice = liveNotice else { return }
        liveNotice = nil
        let before = document.documentContextBeforeInput ?? ""
        switch notice.kind {
        case .suggested:
            if let steps = livePolicy.reconcile(notice.pending, corrected: notice.corrected, contextBefore: before) {
                EditPlanner.apply(steps, to: document)
                _ = recordCorrection(original: notice.pending.original, corrected: notice.corrected)
                notifySuccess()
            }
        case .applied:
            let reverted = PendingCorrection(original: notice.corrected, tail: notice.pending.tail)
            if let steps = livePolicy.reconcile(reverted, corrected: notice.pending.original, contextBefore: before) {
                EditPlanner.apply(steps, to: document)
                if let id = notice.historyID { host?.removeCorrection(id) }
            }
            declined.insert(notice.pending.original)
        }
        updateShiftForContext()
    }

    public func dismissLiveNotice() { liveNotice = nil }

    private func recordCorrection(original: String, corrected: String, languageHint: String? = nil) -> UUID? {
        guard settings.saveCorrectionHistory, let host, host.hasFullAccess else { return nil }
        return host.recordCorrection(original: original, corrected: corrected, languageHint: languageHint)
    }

    // MARK: Feedback

    private func feedback() {
        if settings.keyClickSound { host?.playInputClick() }
        if settings.hapticFeedback, host?.hasFullAccess ?? false { haptics.impactOccurred(intensity: 0.5) }
    }

    private func notifySuccess() {
        if settings.hapticFeedback, host?.hasFullAccess ?? false {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}
#endif
