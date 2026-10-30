import SwiftUI
import UIKit
import WritingCore

/// In-app editor: write or paste, then Fix / Enhance / Translate / Ask AI, review the diff, replace.
struct EditorView: View {
    @EnvironmentObject var model: AppModel
    let openModels: () -> Void

    @State private var text = ""
    @State private var running: WritingAction?
    @State private var partial = ""
    @State private var result: AssistantResult?
    @State private var resultAction: WritingAction?
    @State private var error: String?
    @State private var history: [String] = []
    @State private var task: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    statusBar
                    editor
                    actionBar
                    if let running { workingCard(running) }
                    if let result, let resultAction { resultCard(result, action: resultAction) }
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("editor.error")
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(Brand.name)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { undo() } label: { Image(systemName: "arrow.uturn.backward") }
                        .disabled(history.isEmpty)
                        .accessibilityIdentifier("editor.undo")
                }
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield.fill").foregroundStyle(Palette.accent)
            if let active = model.activeModel {
                Text("On-device · \(active.name)").font(.footnote).foregroundStyle(.secondary)
            } else {
                Button("Download a model to start", action: openModels)
                    .font(.footnote.weight(.semibold))
                    .accessibilityIdentifier("editor.needsModel")
            }
            Spacer()
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("Type or paste text…").foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 5)
            }
            TextEditor(text: $text)
                .focused($focused)
                .frame(minHeight: 160)
                .scrollContentBackground(.hidden)
                .accessibilityIdentifier("editor.text")
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
    }

    private var actionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { run(.fix) } label: {
                    Label("Fix", systemImage: WritingAction.fix.symbol).fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("editor.fix")

                Menu {
                    ForEach(WritingAction.enhance) { action in
                        Button { run(action) } label: { Label(action.title, systemImage: action.symbol) }
                    }
                } label: { Label("Enhance", systemImage: "wand.and.stars") }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("editor.enhance")

                Menu {
                    ForEach(WritingAction.translate) { action in
                        Button { run(action) } label: { Label(action.title, systemImage: action.symbol) }
                    }
                } label: { Label("Translate", systemImage: "globe") }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("editor.translate")

                Button { run(.ask) } label: { Image(systemName: WritingAction.ask.symbol) }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Ask AI")
                    .accessibilityIdentifier("editor.ask")
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
        .disabled(running != nil || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func workingCard(_ action: WritingAction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ProgressView()
                Text("\(action.title) on-device…").font(.subheadline.weight(.semibold))
                Spacer()
                Button("Stop") { task?.cancel(); running = nil }
            }
            if !partial.isEmpty { Text(partial).foregroundStyle(.secondary) }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.accent.opacity(0.4)))
    }

    private func resultCard(_ result: AssistantResult, action: WritingAction) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(action.title).font(.headline)
                Spacer()
                Text(String(format: "%.2fs", result.stats.totalSeconds))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .accessibilityIdentifier("editor.latency")
            }
            if result.hasChanges {
                Text(Self.attributed(result.segments, showRemoved: action == .fix))
                    .textSelection(.enabled)
                    .accessibilityIdentifier("editor.result")
                    .accessibilityValue(result.output)
                if action == .fix, !result.changes.isEmpty {
                    Text(result.changes.prefix(6).joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Label(result.rejectedChunks > 0 ? "No safe suggestion for this text." : "Looks good — nothing to fix.",
                      systemImage: "checkmark.seal")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("editor.noChanges")
            }
            HStack {
                if result.hasChanges {
                    Button("Replace") { replace(with: result.output) }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("editor.replace")
                    Button { UIPasteboard.general.string = result.output } label: { Label("Copy", systemImage: "doc.on.doc") }
                        .accessibilityIdentifier("editor.copy")
                    ShareLink(item: result.output) { Image(systemName: "square.and.arrow.up") }
                }
                Spacer()
                Button { run(action) } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Retry")
                    .accessibilityIdentifier("editor.retry")
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
    }

    private func run(_ action: WritingAction) {
        focused = false
        task?.cancel()
        error = nil
        result = nil
        partial = ""
        running = action
        let input = text
        task = Task {
            do {
                let assistant = try await model.assistant()
                let output = try await assistant.run(actionID: action.id, text: input) { p in
                    Task { @MainActor in partial = p }
                }
                if Task.isCancelled { return }
                result = output
                resultAction = action
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
            }
            running = nil
        }
    }

    private func replace(with output: String) {
        history.append(text)
        text = output
        result = nil
    }

    private func undo() {
        guard let last = history.popLast() else { return }
        text = last
    }

    static func attributed(_ segments: [TextDiff.Segment], showRemoved: Bool) -> AttributedString {
        var out = AttributedString()
        for segment in segments {
            var part = AttributedString(segment.text)
            switch segment.kind {
            case .equal: break
            case .inserted:
                part.foregroundColor = Palette.inserted
                part.font = .body.bold()
            case .removed:
                guard showRemoved else { continue }
                part.foregroundColor = Palette.removed
                part.strikethroughStyle = .single
            }
            out += part
        }
        return out
    }
}
