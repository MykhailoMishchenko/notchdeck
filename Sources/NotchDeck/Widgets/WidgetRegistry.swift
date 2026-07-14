import Foundation
import Combine

// inputs {}, does {single registration point for widgets: display order + persistence, visibility lifecycle, poll timers, live-lock aggregation, takeover host}, returns {observable registry}
final class WidgetRegistry: ObservableObject, WidgetHost {
    @Published private(set) var widgets: [NotchWidget] = []
    /// Widget currently holding the full panel (nil = normal card row).
    @Published var takeoverId: String?

    private let orderKey = "dev.notchdeck.widgetOrder"
    private var pollTimers: [String: Timer] = [:]
    private var visiblePanels = 0

    // inputs {widget}, does {adds a widget (id must be unique) and applies the persisted order}, returns {}
    func register(_ widget: NotchWidget) {
        guard !widgets.contains(where: { $0.id == widget.id }) else {
            Log.info("widget \(widget.id): duplicate registration ignored")
            return
        }
        widgets.append(widget)
        widget.attach(host: self)
        applyPersistedOrder()
        Log.info("widget registered: \(widget.id)")
    }

    // inputs {draggedId, targetId}, does {moves the dragged widget to the target's position (drag&drop reorder) and persists the order}, returns {}
    func move(_ draggedId: String, before targetId: String) {
        guard draggedId != targetId,
              let from = widgets.firstIndex(where: { $0.id == draggedId }),
              let to = widgets.firstIndex(where: { $0.id == targetId }) else { return }
        widgets.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        persistOrder()
    }

    /// True while any visible widget reports a live update in progress.
    var holdsExpanded: Bool {
        visiblePanels > 0 && widgets.contains { $0.holdsExpanded }
    }

    /// Total width widgets currently occupy beside the cutout in the collapsed strip (hit-zone math).
    var collapsedAccessoryWidth: CGFloat {
        widgets.map(\.collapsedAccessoryWidth).reduce(0, +)
    }

    // inputs {}, does {a panel expanded; on first visible panel starts widget lifecycle + polling}, returns {}
    func panelDidExpand() {
        visiblePanels += 1
        guard visiblePanels == 1 else { return }
        for widget in widgets {
            widget.onAppear()
            widget.refresh()
            startPolling(widget)
        }
    }

    // inputs {}, does {a panel collapsed; when none remain visible stops polling + widget lifecycle and resets takeover}, returns {}
    func panelDidCollapse() {
        visiblePanels = max(0, visiblePanels - 1)
        guard visiblePanels == 0 else { return }
        pollTimers.values.forEach { $0.invalidate() }
        pollTimers.removeAll()
        widgets.forEach { $0.onDisappear() }
        takeoverId = nil
    }

    // inputs {}, does {a system file drag entered the strip: hand the panel to the file-accepting widget}, returns {}
    func beginFileDropTakeover() {
        guard takeoverId == nil else { return }
        takeoverId = widgets.first { $0.acceptsFileDrops }?.id
    }

    // inputs {widget}, does {starts the poll timer for a poll-based widget}, returns {}
    private func startPolling(_ widget: NotchWidget) {
        guard let interval = widget.updateInterval else { return }
        pollTimers[widget.id] = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak widget] _ in
            widget?.refresh()
        }
    }

    // inputs {widgetId}, does {WidgetHost: enter/exit full-panel takeover}, returns {}
    func requestTakeover(_ widgetId: String) {
        takeoverId = widgetId
    }

    func endTakeover() {
        takeoverId = nil
    }

    // inputs {}, does {saves current widget id order to UserDefaults}, returns {}
    private func persistOrder() {
        UserDefaults.standard.set(widgets.map(\.id), forKey: orderKey)
    }

    // inputs {}, does {reorders widgets to match the persisted id order (unknown ids keep registration order at the end)}, returns {}
    private func applyPersistedOrder() {
        guard let saved = UserDefaults.standard.stringArray(forKey: orderKey) else { return }
        // Swift's sort is not stable — tiebreak equal (unsaved) keys by current position.
        widgets = widgets.enumerated().sorted { lhs, rhs in
            let a = saved.firstIndex(of: lhs.element.id) ?? Int.max
            let b = saved.firstIndex(of: rhs.element.id) ?? Int.max
            return a == b ? lhs.offset < rhs.offset : a < b
        }.map(\.element)
    }
}
