import AppKit
import SwiftUI
import UniformTypeIdentifiers

// inputs {}, does {observable shelf contents}, returns {model}
final class FilesShelfModel: ObservableObject {
    @Published var files: [URL] = []
}

// inputs {}, does {files shelf widget: drag&drop into temp storage, AirDrop via NSSharingService, clear}, returns {NotchWidget}
final class FilesShelfWidget: NotchWidget {
    let id = "files"
    let displayName = "Files"
    private let model = FilesShelfModel()
    private let shelfDir: URL

    init() {
        shelfDir = FileManager.default.temporaryDirectory.appendingPathComponent("NotchDeckShelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: shelfDir, withIntermediateDirectories: true)
    }

    var expandedView: AnyView {
        AnyView(FilesShelfCardView(
            model: model,
            onDropped: { [weak self] urls in self?.add(urls) },
            onAirDrop: { [weak self] in self?.airDrop() },
            onClear: { [weak self] in self?.clear() }
        ))
    }

    // inputs {urls}, does {copies dropped files into the temp shelf (unique names) and lists them}, returns {}
    private func add(_ urls: [URL]) {
        for url in urls {
            var dest = shelfDir.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                dest = shelfDir.appendingPathComponent("\(UUID().uuidString.prefix(6))-\(url.lastPathComponent)")
            }
            do {
                try FileManager.default.copyItem(at: url, to: dest)
                model.files.append(dest)
                Log.info("shelf: added \(dest.lastPathComponent)")
            } catch {
                Log.info("shelf: copy failed \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    // inputs {}, does {opens the AirDrop sharing sheet with the shelf contents}, returns {}
    private func airDrop() {
        guard !model.files.isEmpty else { return }
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: model.files)
    }

    // inputs {}, does {empties the shelf and removes the temp copies}, returns {}
    private func clear() {
        model.files.forEach { try? FileManager.default.removeItem(at: $0) }
        model.files.removeAll()
    }
}

// inputs {model, callbacks}, does {shelf card UI: drop zone / file icons + AirDrop + clear}, returns {View}
struct FilesShelfCardView: View {
    @ObservedObject var model: FilesShelfModel
    let onDropped: ([URL]) -> Void
    let onAirDrop: () -> Void
    let onClear: () -> Void
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 6) {
            if model.files.isEmpty {
                Image(systemName: "tray.and.arrow.down")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(isTargeted ? 0.9 : 0.4))
                Text("Drop files here")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                HStack(spacing: 4) {
                    ForEach(model.files.suffix(4), id: \.self) { url in
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .frame(width: 24, height: 24)
                    }
                }
                Text("\(model.files.count) file\(model.files.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                HStack(spacing: 12) {
                    Button(action: onAirDrop) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    Button(action: onClear) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    Color.white.opacity(isTargeted ? 0.5 : 0),
                    style: StrokeStyle(lineWidth: 1, dash: [4])
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            for provider in providers {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    DispatchQueue.main.async { onDropped([url]) }
                }
            }
            return true
        }
    }
}
