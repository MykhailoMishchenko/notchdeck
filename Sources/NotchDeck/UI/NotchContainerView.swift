import SwiftUI

// inputs {expanded flag}, does {shared hover/expand state between AppKit controller and SwiftUI}, returns {observable}
final class NotchState: ObservableObject {
    @Published var expanded = false {
        didSet {
            guard expanded != oldValue else { return }
            Log.info("state: \(expanded ? "expanded" : "collapsed")")
            onExpandedChange(expanded)
            expanded ? startWatchdog() : stopWatchdog()
        }
    }
    /// Set by the controller: feeds the widget registry's visibility lifecycle.
    var onExpandedChange: (Bool) -> Void = { _ in }
    private var collapseWork: DispatchWorkItem?
    /// Set by the controller: is the REAL cursor currently inside the interactive zone (screen coords).
    /// Hover events are noisy while the shape animates; cursor position is the source of truth.
    var isCursorInZone: () -> Bool = { false }
    /// Set by the controller: a visible widget holds the panel open (live-lock). Re-checked every second.
    var isCollapseBlocked: () -> Bool = { false }

    private var watchdog: Timer?

    deinit {
        watchdog?.invalidate()
    }

    // inputs {hovering}, does {expands immediately on hover-in; on hover-out collapses after a grace delay, unless the cursor is still in the zone or a widget live-lock blocks it (then re-checks in 1s)}, returns {}
    func setHovering(_ hovering: Bool) {
        collapseWork?.cancel()
        if hovering {
            expanded = true
        } else {
            scheduleCollapse(after: 0.10)
        }
    }

    // inputs {}, does {safety net while expanded: hover exit events get swallowed by system gestures (Space switch, Mission Control), so re-check the real cursor position every 0.5s and collapse if it left the zone}, returns {}
    private func startWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.expanded else { return }
            if !self.isCursorInZone(), !self.isCollapseBlocked() {
                Log.info("watchdog: cursor left zone without exit event — collapsing")
                self.expanded = false
            }
        }
    }

    // inputs {}, does {stops the expanded-state watchdog}, returns {}
    private func stopWatchdog() {
        watchdog?.invalidate()
        watchdog = nil
    }

    // inputs {delay}, does {schedules a collapse attempt; aborts if cursor returned, retries later if live-locked}, returns {}
    private func scheduleCollapse(after delay: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isCursorInZone() else { return }
            if self.isCollapseBlocked() {
                self.scheduleCollapse(after: 1.0)
                return
            }
            self.expanded = false
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

// inputs {}, does {reports the collapsed strip's self-measured width up the tree}, returns {preference key}
struct CollapsedWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// inputs {state, registry, geometry, hasNotch, expandedSize, slops}, does {renders the self-sizing collapsed strip (with Dynamic-Island widget slots) and the hover-expanded panel with spring animation}, returns {View}
struct NotchContainerView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var registry: WidgetRegistry
    let hasNotch: Bool
    let geometry: NotchGeometry
    let expandedSize: CGSize
    let collapsedSlopX: CGFloat
    let collapsedSlopY: CGFloat
    let expandedSlop: CGFloat
    /// Screen-space check from the controller: is the dragged file close to this screen's notch.
    let isDragNear: (CGPoint) -> Bool

    @State private var collapsedContentWidth: CGFloat = 0
    @State private var stripDropTargeted = false
    @ObservedObject private var dragMonitor = FileDragMonitor.shared

    /// File drag close to the strip: it stretches toward the cursor (wider AND taller).
    private var dragNear: Bool {
        dragMonitor.draggingFiles && isDragNear(dragMonitor.dragLocation)
    }

    private var collapsedBaseWidth: CGFloat { geometry.notchWidth + geometry.topCornerRadius * 2 }
    private var bottomRadius: CGFloat { state.expanded ? 24 : geometry.bottomCornerRadius }
    /// The single always-present frame both states morph between — this is what the spring interpolates.
    private var currentWidth: CGFloat {
        state.expanded ? expandedSize.width : max(collapsedBaseWidth, collapsedContentWidth)
    }
    private var currentHeight: CGFloat {
        state.expanded ? expandedSize.height : geometry.notchHeight + (dragNear ? 14 : 0)
    }
    /// Hover zone is larger than the visible shape so expansion triggers on approach.
    private var hoverWidth: CGFloat {
        state.expanded ? expandedSize.width : currentWidth + collapsedSlopX * 2
    }
    private var hoverHeight: CGFloat {
        state.expanded ? expandedSize.height + expandedSlop : currentHeight + collapsedSlopY
    }
    private var shape: NotchShape {
        NotchShape(topCornerRadius: geometry.topCornerRadius, bottomCornerRadius: bottomRadius)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                if state.expanded {
                    WidgetPanelView(registry: registry)
                        .padding(.top, geometry.notchHeight)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                        .transition(.asymmetric(
                            insertion: .opacity.animation(.easeOut(duration: 0.15).delay(0.15)),
                            removal: .opacity.animation(.easeIn(duration: 0.08))
                        ))
                } else {
                    collapsedStrip
                        .transition(.opacity.animation(.easeOut(duration: 0.12)))
                }
            }
            .frame(width: currentWidth, height: currentHeight, alignment: .top)
            .background(shape.fill(Color.black))
            .clipShape(shape)
            .frame(width: hoverWidth, height: hoverHeight, alignment: .top)
            .contentShape(Rectangle())
            .onHover { state.setHovering($0) }
            .animation(
                .spring(response: state.expanded ? 0.38 : 0.30, dampingFraction: 0.78),
                value: state.expanded
            )
            .animation(.spring(response: 0.30, dampingFraction: 0.80), value: collapsedContentWidth)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: dragNear)
            .onPreferenceChange(CollapsedWidthPreferenceKey.self) { collapsedContentWidth = $0 }
            .onChange(of: stripDropTargeted) { targeted in
                guard targeted, !state.expanded else { return }
                registry.beginFileDropTakeover()
                state.expanded = true
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// The cutout gap stays fixed; widget slot views sit beside it and stretch the black shape when active.
    /// During a system file drag the strip widens as a "you can drop here" hint, and a drag entering it
    /// expands the panel straight into the file-drop takeover.
    private var collapsedStrip: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(registry.activeWidgets, id: \.id) { widget in widget.collapsedLeading }
            }
            Color.clear.frame(width: collapsedBaseWidth)
            HStack(spacing: 0) {
                ForEach(registry.activeWidgets, id: \.id) { widget in widget.collapsedTrailing }
            }
        }
        .padding(.horizontal, dragMonitor.draggingFiles ? (dragNear ? 30 : 20) : 0)
        .frame(height: geometry.notchHeight)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: CollapsedWidthPreferenceKey.self, value: proxy.size.width)
            }
        )
        .onDrop(of: [.fileURL], isTargeted: $stripDropTargeted) { _ in false }
    }
}
