import AppKit
import SwiftUI

// inputs {screen}, does {owns one NotchWindow per screen: computes frames, hosts SwiftUI, exposes interactive zone for hit-testing}, returns {controller}
final class NotchWindowController {
    let screen: NSScreen
    let hasNotch: Bool
    let geometry: NotchGeometry
    let state = NotchState()

    private let window: NotchWindow
    private let expandedSize = CGSize(width: 640, height: 240)
    private let hoverSlop: CGFloat = 4

    init(screen: NSScreen) {
        self.screen = screen
        if let detected = NotchGeometry.detect(for: screen) {
            self.geometry = detected
            self.hasNotch = true
        } else {
            self.geometry = .pill
            self.hasNotch = false
        }

        let windowWidth = expandedSize.width + 80
        let windowHeight = expandedSize.height + 40
        let frame = NSRect(
            x: screen.frame.midX - windowWidth / 2,
            y: screen.frame.maxY - windowHeight,
            width: windowWidth,
            height: windowHeight
        )
        window = NotchWindow(contentRect: frame)

        let root = NotchContainerView(
            state: state,
            hasNotch: hasNotch,
            geometry: geometry,
            expandedSize: expandedSize
        )
        let hosting = PassThroughHostingView(rootView: root)
        hosting.interactiveRect = { [weak self] in self?.interactiveRect() ?? .zero }
        window.contentView = hosting
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
        Log.info("window up: screen=\(screen.localizedName) mode=\(hasNotch ? "notch" : "pill") geometry=\(Int(geometry.notchWidth))x\(Int(geometry.notchHeight))")
    }

    // inputs {}, does {returns the currently interactive zone in view coordinates measured from the TOP edge (converted by hitTest caller)}, returns {rect}
    private func interactiveRect() -> CGRect {
        guard let view = window.contentView else { return .zero }
        let bounds = view.bounds
        let width: CGFloat
        let height: CGFloat
        if state.expanded {
            width = expandedSize.width
            height = expandedSize.height + hoverSlop
        } else {
            width = geometry.notchWidth + geometry.topCornerRadius * 2 + hoverSlop * 2
            height = geometry.notchHeight + hoverSlop
        }
        let x = bounds.midX - width / 2
        // Hosting view coords: NSHostingView is flipped (origin top-left), so top zone starts at y = 0.
        let y: CGFloat = view.isFlipped ? 0 : bounds.height - height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    // inputs {}, does {closes and releases the window (screen disconnected)}, returns {}
    func tearDown() {
        window.close()
    }
}
