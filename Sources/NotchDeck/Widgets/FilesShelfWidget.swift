import AppKit
import SwiftUI

// inputs {}, does {observable shelf contents}, returns {model}
final class FilesShelfModel: ObservableObject {
    @Published var files: [URL] = []
}

// inputs {}, does {files buffer widget: drops MOVE files into a persistent shelf (cut semantics), drag-out to Finder moves them on, drag to apps shares; survives restarts; deletions go to the system Trash}, returns {NotchWidget}
final class FilesShelfWidget: NotchWidget {
    let id = "files"
    let displayName = "Files"
    private let model = FilesShelfModel()
    private let shelfDir: URL
    private weak var host: WidgetHost?

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        shelfDir = appSupport.appendingPathComponent("NotchDeck/Shelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: shelfDir, withIntermediateDirectories: true)
        loadExistingShelf()
    }

    /// 0 = no card in the panel row: the tray lives in its takeover, opened from the launcher square or a file drag.
    var expandedWidthWeight: CGFloat { 0 }
    var acceptsFileDrops: Bool { true }
    var launcherIcon: String { "tray.full" }
    var launcherBadge: String? { model.files.isEmpty ? nil : "\(model.files.count)" }

    func attach(host: WidgetHost) {
        self.host = host
    }

    var expandedView: AnyView { AnyView(EmptyView()) }

    var takeoverView: AnyView {
        AnyView(FilesTakeoverView(
            model: model,
            onDropped: { [weak self] urls in self?.add(urls) },
            onDragOutCompleted: { [weak self] url in self?.removeAfterDragOut(url) },
            onClear: { [weak self] in self?.clear() },
            onBack: { [weak self] in self?.host?.endTakeover() }
        ))
    }

    // inputs {}, does {restores the buffer from disk on launch (the shelf is persistent)}, returns {}
    private func loadExistingShelf() {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: shelfDir,
            includingPropertiesForKeys: [.addedToDirectoryDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        model.files = contents.sorted { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.addedToDirectoryDateKey]).addedToDirectoryDate) ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: [.addedToDirectoryDateKey]).addedToDirectoryDate) ?? .distantPast
            return l < r
        }
        if !model.files.isEmpty { Log.info("shelf: restored \(model.files.count) items") }
    }

    // inputs {urls}, does {MOVES dropped files/folders into the shelf (cut semantics; copy+delete fallback across volumes)}, returns {}
    private func add(_ urls: [URL]) {
        for url in urls {
            var dest = shelfDir.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                dest = shelfDir.appendingPathComponent("\(UUID().uuidString.prefix(6))-\(url.lastPathComponent)")
            }
            do {
                do {
                    try FileManager.default.moveItem(at: url, to: dest)
                } catch {
                    try FileManager.default.copyItem(at: url, to: dest)
                    try? FileManager.default.removeItem(at: url)
                }
                model.files.append(dest)
                Log.info("shelf: moved in \(dest.lastPathComponent)")
            } catch {
                Log.info("shelf: move failed \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    // inputs {shelf url}, does {item moved to a Finder folder: drop it from the list now, trash the shelf copy after 60s (large folder copies must finish; Trash is recoverable)}, returns {}
    private func removeAfterDragOut(_ url: URL) {
        model.files.removeAll { $0 == url }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        Log.info("shelf: moved out \(url.lastPathComponent)")
    }

    // inputs {}, does {empties the buffer into the system Trash (recoverable — the shelf holds the only copy)}, returns {}
    private func clear() {
        model.files.forEach { try? FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
        model.files.removeAll()
        Log.info("shelf: cleared to Trash")
    }
}
