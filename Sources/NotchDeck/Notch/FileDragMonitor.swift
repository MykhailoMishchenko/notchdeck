import AppKit
import Combine

// inputs {}, does {watches system-wide mouse drags and flips draggingFiles while the drag pasteboard carries file URLs — powers the "notch is a drop target" hint}, returns {observable singleton}
final class FileDragMonitor: ObservableObject {
    static let shared = FileDragMonitor()

    @Published var draggingFiles = false
    /// Current cursor position during a file drag (screen coords, throttled) — powers the proximity stretch.
    @Published var dragLocation: CGPoint = .zero
    private var monitors: [Any] = []
    private var handledChangeCount = -1

    // inputs {}, does {installs global mouse monitors (no special permissions needed for mouse events)}, returns {}
    func start() {
        guard monitors.isEmpty else { return }
        if let drag = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: { [weak self] _ in
            self?.checkDragPasteboard()
        }) {
            monitors.append(drag)
        }
        if let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in
            self?.endDrag()
        }) {
            monitors.append(up)
        }
    }

    // inputs {}, does {marks a new drag session as file-carrying by inspecting the drag pasteboard once per changeCount; tracks the cursor while dragging}, returns {}
    private func checkDragPasteboard() {
        if draggingFiles {
            updateLocation()
        }
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != handledChangeCount else { return }
        handledChangeCount = pasteboard.changeCount
        let hasFiles = pasteboard.types?.contains(.fileURL) == true
        if hasFiles != draggingFiles {
            draggingFiles = hasFiles
            updateLocation()
            Log.info("file drag: \(hasFiles ? "started" : "not files")")
        }
    }

    // inputs {}, does {publishes the cursor position, throttled to ~6pt steps to keep SwiftUI churn low}, returns {}
    private func updateLocation() {
        let location = NSEvent.mouseLocation
        if abs(location.x - dragLocation.x) > 6 || abs(location.y - dragLocation.y) > 6 {
            dragLocation = location
        }
    }

    // inputs {}, does {drag session ended (mouse up anywhere)}, returns {}
    private func endDrag() {
        guard draggingFiles else { return }
        draggingFiles = false
        Log.info("file drag: ended")
    }
}
