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

    @State private var collapsedContentWidth: CGFloat = 0

    private var collapsedBaseWidth: CGFloat { geometry.notchWidth + geometry.topCornerRadius * 2 }
    private var bottomRadius: CGFloat { state.expanded ? 24 : geometry.bottomCornerRadius }
    /// Hover zone is larger than the visible shape so expansion triggers on approach.
    private var hoverWidth: CGFloat {
        state.expanded
            ? expandedSize.width
            : max(collapsedBaseWidth, collapsedContentWidth) + collapsedSlopX * 2
    }
    private var hoverHeight: CGFloat {
        state.expanded ? expandedSize.height + expandedSlop : geometry.notchHeight + collapsedSlopY
    }
    private var shape: NotchShape {
        NotchShape(topCornerRadius: geometry.topCornerRadius, bottomCornerRadius: bottomRadius)
    }

    var body: some View {
        VStack(spacing: 0) {
            content
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
                .onPreferenceChange(CollapsedWidthPreferenceKey.self) { collapsedContentWidth = $0 }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder private var content: some View {
        if state.expanded {
            WidgetPanelView(registry: registry)
                .padding(.top, geometry.notchHeight)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .frame(width: expandedSize.width, height: expandedSize.height)
                .transition(.asymmetric(
                    insertion: .opacity.animation(.easeOut(duration: 0.15).delay(0.15)),
                    removal: .opacity.animation(.easeIn(duration: 0.08))
                ))
        } else {
            collapsedStrip
        }
    }

    /// The cutout gap stays fixed; widget slot views sit beside it and stretch the black shape when active.
    private var collapsedStrip: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(registry.widgets, id: \.id) { widget in widget.collapsedLeading }
            }
            Color.clear.frame(width: collapsedBaseWidth)
            HStack(spacing: 0) {
                ForEach(registry.widgets, id: \.id) { widget in widget.collapsedTrailing }
            }
        }
        .frame(height: geometry.notchHeight)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: CollapsedWidthPreferenceKey.self, value: proxy.size.width)
            }
        )
    }
}
