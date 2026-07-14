import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

// inputs {providers, completion}, does {extracts file URLs from drop providers and delivers them on main}, returns {}
func loadDroppedURLs(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
    let group = DispatchGroup()
    var urls: [URL] = []
    let lock = NSLock()
    for provider in providers {
        group.enter()
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            defer { group.leave() }
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            lock.lock()
            urls.append(url)
            lock.unlock()
        }
    }
    group.notify(queue: .main) { completion(urls) }
}

// inputs {model, callbacks}, does {full-panel takeover: full-width dashed Files Tray grid; back via swipe-right or chevron}, returns {View}
struct FilesTakeoverView: View {
    @ObservedObject var model: FilesShelfModel
    let onDropped: ([URL]) -> Void
    let onDragOutCompleted: (URL) -> Void
    let onClear: () -> Void
    let onBack: () -> Void

    @State private var trayTargeted = false

    var body: some View {
        // Back navigation (chevron + swipe) is provided by the platform takeover wrapper.
        trayZone
    }

    private var trayZone: some View {
        Group {
            if model.files.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(trayTargeted ? 0.95 : 0.55))
                    Text("Files Tray")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 4) {
                    ScrollView(showsIndicators: false) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 8)], spacing: 8) {
                            ForEach(model.files, id: \.self) { url in
                                FileTrayItemView(url: url) { onDragOutCompleted(url) }
                            }
                        }
                        .padding(.top, 12)
                        .padding(.horizontal, 14)
                    }
                    HStack(spacing: 10) {
                        Text("\(model.files.count) file\(model.files.count == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.55))
                        Button(action: onClear) {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 6)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(trayTargeted ? 0.08 : 0.03)))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    .white.opacity(trayTargeted ? 0.75 : 0.35),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $trayTargeted) { providers in
            loadDroppedURLs(providers) { onDropped($0) }
            return true
        }
    }
}

// inputs {url, onDraggedOut}, does {one tray item: preview/icon + filename; drag OUT via a real NSDraggingSource so a successful external drop removes it from the tray}, returns {View}
struct FileTrayItemView: View {
    let url: URL
    let onDraggedOut: () -> Void
    @State private var thumbnail: NSImage?
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 3) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .scaledToFit()
                }
            }
            .frame(width: 38, height: 38)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .scaleEffect(hovered ? 1.15 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovered)
            .overlay(
                DragOutSourceView(
                    url: url,
                    dragImage: thumbnail ?? NSWorkspace.shared.icon(forFile: url.path),
                    onHover: { hovered = $0 },
                    onDraggedOut: onDraggedOut
                )
            )
            Text(url.lastPathComponent)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 56)
        }
        .help(url.lastPathComponent)
        .onAppear { generateThumbnail() }
    }

    // inputs {}, does {asks QuickLook for a real content thumbnail; keeps the macOS file icon when none exists}, returns {}
    private func generateThumbnail() {
        guard thumbnail == nil else { return }
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard !isDirectory.boolValue else { return }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 76, height: 76),
            scale: 2,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            guard let cgImage = representation?.cgImage else { return }
            DispatchQueue.main.async {
                thumbnail = NSImage(cgImage: cgImage, size: .zero)
            }
        }
    }
}

// inputs {url, dragImage, onHover, onDraggedOut}, does {AppKit drag source: hover tracking + beginDraggingSession; fires onDraggedOut only when the drop was ACCEPTED outside our app (the session-end callback SwiftUI's onDrag lacks)}, returns {NSViewRepresentable}
struct DragOutSourceView: NSViewRepresentable {
    let url: URL
    let dragImage: NSImage
    let onHover: (Bool) -> Void
    let onDraggedOut: () -> Void

    func makeNSView(context: Context) -> SourceNSView {
        let view = SourceNSView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: SourceNSView, context: Context) {
        update(nsView)
    }

    private func update(_ view: SourceNSView) {
        view.url = url
        view.dragImage = dragImage
        view.onHover = onHover
        view.onDraggedOut = onDraggedOut
    }

    final class SourceNSView: NSView, NSDraggingSource {
        var url: URL?
        var dragImage: NSImage?
        var onHover: (Bool) -> Void = { _ in }
        var onDraggedOut: () -> Void = {}
        private var mouseDownEvent: NSEvent?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self,
                userInfo: nil
            ))
        }

        override func mouseEntered(with event: NSEvent) { onHover(true) }
        override func mouseExited(with event: NSEvent) { onHover(false) }
        override func mouseDown(with event: NSEvent) { mouseDownEvent = event }

        override func mouseDragged(with event: NSEvent) {
            guard let mouseDownEvent, let url else { return }
            self.mouseDownEvent = nil
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let image = dragImage ?? NSWorkspace.shared.icon(forFile: url.path)
            item.setDraggingFrame(bounds, contents: image)
            beginDraggingSession(with: [item], event: mouseDownEvent, source: self)
        }

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            context == .outsideApplication ? .copy : []
        }

        // Buffer semantics: dropping into Finder (a folder / the Desktop) MOVES the item out of the tray;
        // dropping into any app (Telegram, a browser...) SHARES it — the item stays.
        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            guard !operation.isEmpty else { return }
            let finderDestination = Self.isFinderDestination(at: screenPoint)
            Log.info("shelf: drag-out accepted, destination=\(finderDestination ? "finder (move)" : "app (keep)")")
            guard finderDestination else { return }
            DispatchQueue.main.async { [onDraggedOut] in onDraggedOut() }
        }

        // inputs {cocoa screen point}, does {finds the app owning the topmost normal window under the drop point; no window = Desktop}, returns {true when the destination is Finder/Desktop}
        private static func isFinderDestination(at cocoaPoint: NSPoint) -> Bool {
            let cgPoint = CGPoint(
                x: cocoaPoint.x,
                y: CGDisplayBounds(CGMainDisplayID()).height - cocoaPoint.y
            )
            guard let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
            ) as? [[String: Any]] else { return false }
            let ownPid = Int(ProcessInfo.processInfo.processIdentifier)
            for entry in windows {
                guard
                    let pid = entry[kCGWindowOwnerPID as String] as? Int, pid != ownPid,
                    let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                    let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                    let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                    rect.contains(cgPoint)
                else { continue }
                let bundleId = NSRunningApplication(processIdentifier: pid_t(pid))?.bundleIdentifier
                return bundleId == "com.apple.finder"
            }
            // No normal window under the point — the drop landed on the Desktop (Finder territory).
            return true
        }
    }
}
