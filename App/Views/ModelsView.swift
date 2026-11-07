import SwiftUI
import WritingCore

struct ModelsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        List {
            Section {
                ForEach(model.catalog.models) { info in
                    ModelRow(info: info)
                }
            } footer: {
                Text("Download a model once, then use it offline in your keyboard. Files are checked after download. Keep this app open until the download finishes.")
            }
        }
        .navigationTitle("Models")
        .onAppear { model.refresh() }
    }
}

struct ModelRow: View {
    @EnvironmentObject var model: AppModel
    let info: ModelInfo
    @State private var confirmDelete = false
    @State private var deleteError: String?

    private var isInstalled: Bool { model.installed.contains(info.id) }
    private var isActive: Bool { model.activeModel?.id == info.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(info.name).font(.headline)
                Spacer()
                if isActive {
                    Label("In use", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(Palette.accent)
                }
            }
            if info.id == model.catalog.defaultModelID {
                Text("Recommended").font(.caption.weight(.semibold)).foregroundStyle(Palette.accent)
            }
            Text(info.summary).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Label(info.sizeDescription, systemImage: "arrow.down.circle")
                Link(info.license, destination: info.licenseURL)
            }
            .font(.caption).foregroundStyle(.secondary)
            actions
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("models.row.\(info.id)")
        .confirmationDialog("Delete \(info.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete model", role: .destructive) {
                do { try model.delete(info) } catch { deleteError = error.localizedDescription }
            }
        } message: {
            Text("You will need to download it again to use it offline.")
        }
        .alert("Could not delete model", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) { deleteError = nil }
        } message: { Text(deleteError ?? "") }
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
            HStack { ProgressView(); Text("Checking download…").font(.caption) }
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
                    Spacer()
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Delete \(info.name)")
                } else {
                    Button("Download") { model.download(info) }.buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("models.download.\(info.id)")
                }
            }
        }
    }
}
