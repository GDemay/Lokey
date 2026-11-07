import SwiftUI
import WritingCore

struct CorrectionHistoryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var items: [CorrectionHistory.Item] = []
    @State private var sortByFrequency = false
    @State private var language: String?
    @State private var isLoading = true
    @State private var confirmClear = false
    @State private var historyError: String?

    private var languages: [String] {
        Set(items.map { $0.correction.languageCode ?? "und" })
            .sorted { languageName($0).localizedStandardCompare(languageName($1)) == .orderedAscending }
    }

    private var visibleItems: [CorrectionHistory.Item] {
        let filtered = language.map { selected in
            items.filter { ($0.correction.languageCode ?? "und") == selected }
        } ?? items
        guard sortByFrequency else { return filtered }
        return filtered.sorted { a, b in
            a.count == b.count ? a.lastSeen > b.lastSeen : a.count > b.count
        }
    }

    var body: some View {
        List {
            Section {
                Toggle("Save corrections", isOn: $model.settings.saveCorrectionHistory)
                    .accessibilityIdentifier("learn.enabled")
            } footer: {
                Text("Lokey saves short excerpts from applied corrections on this iPhone. The keyboard needs Full Access to save them.")
            }

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if items.isEmpty && historyError == nil {
                ContentUnavailableView("No corrections yet", systemImage: "book.closed",
                                       description: Text("Turn on saving and use Fix. Applied corrections will appear here."))
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("learn.empty")
            } else if !items.isEmpty {
                Section {
                    if languages.count > 1 {
                        Picker("Language", selection: $language) {
                            Text("All languages").tag(nil as String?)
                            ForEach(languages, id: \.self) { code in
                                Text(languageName(code)).tag(code as String?)
                            }
                        }
                        .accessibilityIdentifier("learn.language")
                    }
                    Picker("Sort corrections", selection: $sortByFrequency) {
                        Text("Recent").tag(false)
                        Text("Most frequent").tag(true)
                    }
                    .pickerStyle(.segmented)
                    ForEach(visibleItems) { item in
                        correctionRow(item)
                    }
                } header: {
                    Text("Your corrections")
                } footer: {
                    Text("Review repeated corrections first and try the corrected form in a new sentence.")
                }
                Section {
                    Button("Clear history", role: .destructive) { confirmClear = true }
                        .accessibilityIdentifier("learn.clear")
                }
            }
            if let historyError {
                Text(historyError).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Correction history")
        .task(id: scenePhase) {
            if scenePhase == .active { await loadHistory() }
        }
        .refreshable { await loadHistory() }
        .confirmationDialog("Clear correction history?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete saved corrections", role: .destructive) {
                Task { await loadHistory(clear: true) }
            }
        } message: {
            Text("This removes the saved examples from this iPhone.")
        }
    }

    private func correctionRow(_ item: CorrectionHistory.Item) -> some View {
        let edit = item.correction
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(languageName(edit.languageCode ?? "und")) · \(edit.lesson.title)")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(item.count == 1 ? "1 time" : "\(item.count) times")
                    .font(.caption.monospacedDigit())
            }
            .foregroundStyle(.secondary)
            if !edit.before.isEmpty {
                Label(edit.before, systemImage: "minus.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Original. \(edit.before)")
            }
            if !edit.after.isEmpty {
                Label(edit.after, systemImage: "checkmark.circle")
                    .foregroundStyle(Palette.accent)
                    .fontWeight(.semibold)
                    .accessibilityLabel("Correction. \(edit.after)")
                    .accessibilityIdentifier("learn.correction")
            }
            Text(edit.after.isEmpty ? "This part was removed in the correction." : edit.lesson.tip)
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private func languageName(_ code: String) -> String {
        if code == "und" { return "Language unknown" }
        return Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    private func loadHistory(clear: Bool = false) async {
        defer { isLoading = false }
        guard let history = CorrectionHistory.shared() else {
            historyError = "Correction history is unavailable on this iPhone."
            return
        }
        do {
            let loaded = try await Task.detached(priority: .utility) {
                if clear { try history.clear() }
                return try history.items()
            }.value
            guard !Task.isCancelled else { return }
            items = loaded
            if let language, !languages.contains(language) { self.language = nil }
            historyError = nil
        } catch {
            guard !Task.isCancelled else { return }
            historyError = clear ? "Could not clear your history." : "Could not load your history."
        }
    }
}
