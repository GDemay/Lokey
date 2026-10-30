import SwiftUI
import WritingCore

struct ModelsView: View {
    @EnvironmentObject var model: AppModel
    @State private var speed: [String: String] = [:]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.catalog.models) { info in
                        ModelRow(info: info, speed: speed[info.id]) { runSpeedTest(info) }
                    }
                } footer: {
                    Text("Models run entirely on this iPhone with llama.cpp. Files are downloaded from Hugging Face and verified with SHA-256. Liquid AI models are under the LFM Open License v1.0.")
                }
            }
            .navigationTitle("Models")
            .onAppear { model.refresh() }
        }
    }

    /// Times a few typical corrections with the selected model on this device.
    private func runSpeedTest(_ info: ModelInfo) {
        model.select(info)
        speed[info.id] = "Testing…"
        Task {
            do {
                let assistant = try await model.assistant()
                let samples = ["i dont know what to do", "Their going to the park later.",
                               "She have two brothers and a cat.", "can you send me the report by tomorow"]
                _ = try await assistant.run(actionID: "fix", text: "warm up")
                var total = GenerationStats()
                for sample in samples {
                    total = total + (try await assistant.run(actionID: "fix", text: sample)).stats
                }
                let perSentence = total.totalSeconds / Double(samples.count)
                let tokPerSec = Double(total.generatedTokens) / max(0.001, total.decodeSeconds)
                speed[info.id] = String(format: "%.2fs per sentence · %.0f tok/s", perSentence, tokPerSec)
            } catch {
                speed[info.id] = error.localizedDescription
            }
        }
    }
}

struct ModelRow: View {
    @EnvironmentObject var model: AppModel
    let info: ModelInfo
    let speed: String?
    let speedTest: () -> Void

    private var isInstalled: Bool { model.installed.contains(info.id) }
    private var isActive: Bool { model.activeModel?.id == info.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(info.name).font(.headline)
                if info.id == model.catalog.defaultModelID {
                    Text("Recommended").font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Palette.accent.opacity(0.15)))
                        .foregroundStyle(Palette.accent)
                }
                Spacer()
                if isActive { Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent) }
            }
            Text(info.summary).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Label(info.sizeDescription, systemImage: "arrow.down.circle")
                Label(info.parameters, systemImage: "cpu")
                Link(info.license, destination: info.licenseURL)
            }
            .font(.caption).foregroundStyle(.secondary)
            if let speed { Text(speed).font(.caption.monospacedDigit()).accessibilityIdentifier("models.speed.\(info.id)") }
            actions
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("models.row.\(info.id)")
    }

    @ViewBuilder private var actions: some View {
        switch model.downloads[info.id] {
        case .downloading(let progress):
            HStack {
                ProgressView(value: progress)
                Text("\(Int(progress * 100))%").font(.caption.monospacedDigit())
                Button("Cancel") { model.cancelDownload(info) }.font(.caption)
            }
        case .verifying:
            HStack { ProgressView(); Text("Verifying…").font(.caption) }
        case .failed(let message):
            HStack {
                Text(message).font(.caption).foregroundStyle(.red)
                Button("Retry") { model.cancelDownload(info); model.download(info) }.font(.caption)
            }
        case nil:
            HStack {
                if isInstalled {
                    if !isActive {
                        Button("Use") { model.select(info) }.buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("models.use.\(info.id)")
                    }
                    Button("Speed test", action: speedTest).buttonStyle(.bordered)
                        .accessibilityIdentifier("models.speedtest.\(info.id)")
                    Spacer()
                    Button(role: .destructive) { model.delete(info) } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                } else {
                    Button("Download") { model.download(info) }.buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("models.download.\(info.id)")
                }
            }
        }
    }
}
