import AppKit
import SwiftUI

// inputs {screen}, does {owns one NotchWindow per screen: computes frames, hosts SwiftUI, exposes interactive zone for hit-testing}, returns {controller}
final class NotchWindowController {
    let screen: NSScreen
    let hasNotch: Bool
    let geometry: NotchGeometry
    let state = NotchState()

    private let window: NotchWindow
    private let expandedSize = CGSize(width: 440, height: 160)
    /// Hover trigger margins around the collapsed notch — bigger than the shape so expansion starts "на подлёте".
    private let collapsedSlopX: CGFloat = 14
    private let collapsedSlopY: CGFloat = 8
    private let expandedSlop: CGFloat = 4

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
            expandedSize: expandedSize,
            collapsedSlopX: collapsedSlopX,
            collapsedSlopY: collapsedSlopY,
            expandedSlop: expandedSlop
        )
        let hosting = PassThroughHostingView(rootView: root)
        hosting.interactiveRect = { [weak self] in self?.interactiveRectInView() ?? .zero }
        state.isCursorInZone = { [weak self] in
            guard let self else { return false }
            return self.interactiveRectInScreen().contains(NSEvent.mouseLocation)
        }
        window.contentView = hosting
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
        Log.info("window up: screen=\(screen.localizedName) mode=\(hasNotch ? "notch" : "pill") geometry=\(Int(geometry.notchWidth))x\(Int(geometry.notchHeight))")
    }

    // inputs {}, does {interactive zone as (x from window left, y from window TOP, w, h) — single source for both converters below}, returns {rect}
    private func interactiveZoneTopBased() -> CGRect {
        let width: CGFloat
        let height: CGFloat
        if state.expanded {
            width = expandedSize.width
            height = expandedSize.height + expandedSlop
        } else {
            width = geometry.notchWidth + geometry.topCornerRadius * 2 + collapsedSlopX * 2
            height = geometry.notchHeight + collapsedSlopY
        }
        return CGRect(x: (window.frame.width - width) / 2, y: 0, width: width, height: height)
    }

    // inputs {}, does {zone in contentView coordinates for hitTest}, returns {rect}
    private func interactiveRectInView() -> CGRect {
        guard let view = window.contentView else { return .zero }
        let zone = interactiveZoneTopBased()
        let y: CGFloat = view.isFlipped ? zone.minY : view.bounds.height - zone.maxY
        return CGRect(x: zone.minX, y: y, width: zone.width, height: zone.height)
    }

    // inputs {}, does {zone in global screen coordinates (bottom-up) for cursor checks}, returns {rect}
    private func interactiveRectInScreen() -> CGRect {
        let zone = interactiveZoneTopBased()
        return CGRect(
            x: window.frame.minX + zone.minX,
            y: window.frame.maxY - zone.maxY,
            width: zone.width,
            height: zone.height
        )
    }

    // inputs {}, does {closes and releases the window (screen disconnected)}, returns {}
    func tearDown() {
        window.close()
    }
}
