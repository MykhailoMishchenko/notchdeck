import AppKit
import SwiftUI

// inputs {}, does {observable shelf contents}, returns {model}
final class FilesShelfModel: ObservableObject {
    @Published var files: [URL] = []
}

// inputs {}, does {files widget: compact Tray card -> full-panel takeover with Files Tray + AirDrop drop zones; temp storage; NSSharingService AirDrop}, returns {NotchWidget}
final class FilesShelfWidget: NotchWidget {
    let id = "files"
    let displayName = "Files"
    private let model = FilesShelfModel()
    private let shelfDir: URL
    private weak var host: WidgetHost?
    /// Source paths already shelved — the same file dropped twice stays a single tray item.
    private var sourcePaths = Set<String>()
    /// Shelf copy path -> original source path (to release the dedup entry when an item leaves).
    private var sourceByShelfPath: [String: String] = [:]

    init() {
        shelfDir = FileManager.default.temporaryDirectory.appendingPathComponent("NotchDeckShelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: shelfDir, withIntermediateDirectories: true)
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

    // inputs {urls}, does {copies dropped files into the temp shelf (unique names, deduped by source) and lists them}, returns {}
    private func add(_ urls: [URL]) {
        for url in urls {
            guard !sourcePaths.contains(url.path) else {
                Log.info("shelf: duplicate skipped \(url.lastPathComponent)")
                continue
            }
            sourcePaths.insert(url.path)
            var dest = shelfDir.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                dest = shelfDir.appendingPathComponent("\(UUID().uuidString.prefix(6))-\(url.lastPathComponent)")
            }
            do {
                try FileManager.default.copyItem(at: url, to: dest)
                model.files.append(dest)
                sourceByShelfPath[dest.path] = url.path
                Log.info("shelf: added \(dest.lastPathComponent)")
            } catch {
                Log.info("shelf: copy failed \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    // inputs {urls}, does {opens the AirDrop sharing sheet for the given items}, returns {}
    private func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
    }

    // inputs {shelf url}, does {removes an item after a successful drag-out (temp copy stays until clear — the receiver may still be reading it)}, returns {}
    private func removeAfterDragOut(_ url: URL) {
        model.files.removeAll { $0 == url }
        if let source = sourceByShelfPath.removeValue(forKey: url.path) {
            sourcePaths.remove(source)
        }
        Log.info("shelf: removed after drag-out \(url.lastPathComponent)")
    }

    // inputs {}, does {empties the shelf and removes the temp copies}, returns {}
    private func clear() {
        model.files.forEach { try? FileManager.default.removeItem(at: $0) }
        model.files.removeAll()
        sourcePaths.removeAll()
        sourceByShelfPath.removeAll()
    }
}
