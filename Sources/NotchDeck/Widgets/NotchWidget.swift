import SwiftUI

// inputs {}, does {contract every widget implements to plug into the platform — no core changes needed to add one}, returns {protocol}
protocol NotchWidget: AnyObject {
    /// Stable unique id; used for order persistence and settings.
    var id: String { get }
    var displayName: String { get }
    /// Shown in the collapsed strip (optional; most widgets show nothing when collapsed).
    var collapsedView: AnyView { get }
    /// Dynamic-Island slots: shown left/right of the camera cutout in the collapsed strip.
    /// Views observe their own models and render empty when inactive.
    var collapsedLeading: AnyView { get }
    var collapsedTrailing: AnyView { get }
    /// Current total width of both collapsed slots (0 = inactive); pulled by the platform for hover/hit-zone math.
    var collapsedAccessoryWidth: CGFloat { get }
    /// Shown as a card inside the expanded panel.
    var expandedView: AnyView { get }
    /// nil = push-based (widget publishes its own updates); otherwise the platform
    /// calls refresh() on this interval while the widget is visible.
    var updateInterval: TimeInterval? { get }
    /// Live-lock: true = "live update in progress, don't collapse the panel".
    /// Polled by the platform at collapse-decision time.
    var holdsExpanded: Bool { get }
    /// Poll target; called by the platform on updateInterval and once on appear.
    func refresh()
    /// Panel became visible on at least one screen.
    func onAppear()
    /// Panel is no longer visible on any screen.
    func onDisappear()
}

extension NotchWidget {
    var collapsedView: AnyView { AnyView(EmptyView()) }
    var collapsedLeading: AnyView { AnyView(EmptyView()) }
    var collapsedTrailing: AnyView { AnyView(EmptyView()) }
    var collapsedAccessoryWidth: CGFloat { 0 }
    var updateInterval: TimeInterval? { nil }
    var holdsExpanded: Bool { false }
    func refresh() {}
    func onAppear() {}
    func onDisappear() {}
}
