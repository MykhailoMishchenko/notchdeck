import AppKit
import SwiftUI

// inputs {contentRect}, does {borderless transparent non-activating panel pinned above the menu bar layer}, returns {panel}
final class NotchWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// inputs {rootView, interactiveRect provider}, does {hosts SwiftUI content but passes mouse events through everywhere outside the current interactive zone (so the invisible window area never blocks menu bar clicks)}, returns {hosting view}
final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    var interactiveRect: () -> CGRect = { .zero }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard interactiveRect().contains(local) else { return nil }
        return super.hitTest(point)
    }
}
