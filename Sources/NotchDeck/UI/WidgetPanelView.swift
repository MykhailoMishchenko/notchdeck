import SwiftUI
import UniformTypeIdentifiers

// inputs {registry}, does {expanded panel content: header row + widget cards with drag&drop reorder}, returns {View}
struct WidgetPanelView: View {
    @ObservedObject var registry: WidgetRegistry
    @State private var draggedId: String?

    private let spacing: CGFloat = 10

    private let launcherWidth: CGFloat = 40

    var body: some View {
        if let takeoverId = registry.takeoverId,
           let widget = registry.activeWidgets.first(where: { $0.id == takeoverId }) {
            widget.takeoverView
        } else {
            cardRow
        }
    }

    /// Cards (weight > 0) + one launcher column of small squares: every weight-0 widget plus Settings.
    /// The launcher sits at the position of the first weight-0 widget (center by default order).
    private var cardRow: some View {
        GeometryReader { proxy in
            let active = registry.activeWidgets
            let cards = active.filter { $0.expandedWidthWeight > 0 }
            let launcherWidgets = active.filter { $0.expandedWidthWeight == 0 }
            let totalWeight = max(1, cards.map(\.expandedWidthWeight).reduce(0, +))
            let segments = cards.count + 1
            let available = proxy.size.width - spacing * CGFloat(max(0, segments - 1)) - launcherWidth
            let launcherIndex = active.firstIndex { $0.expandedWidthWeight == 0 }
                .map { index in active[..<index].filter { $0.expandedWidthWeight > 0 }.count } ?? cards.count

            HStack(spacing: spacing) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { position, widget in
                    if position == launcherIndex {
                        LauncherColumnView(widgets: launcherWidgets, registry: registry)
                            .frame(width: launcherWidth)
                    }
                    WidgetCardView(widget: widget)
                        .frame(width: available * widget.expandedWidthWeight / totalWeight)
                        .onDrag {
                            draggedId = widget.id
                            return NSItemProvider(object: widget.id as NSString)
                        }
                        .onDrop(
                            of: [.text],
                            delegate: WidgetReorderDelegate(
                                targetId: widget.id,
                                draggedId: $draggedId,
                                registry: registry
                            )
                        )
                }
                if launcherIndex >= cards.count {
                    LauncherColumnView(widgets: launcherWidgets, registry: registry)
                        .frame(width: launcherWidth)
                }
            }
        }
    }
}

// inputs {widgets, registry}, does {vertical column of small squares: weight-0 widgets (open their takeover) + Settings gear}, returns {View}
struct LauncherColumnView: View {
    let widgets: [NotchWidget]
    let registry: WidgetRegistry

    var body: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            ForEach(widgets, id: \.id) { widget in
                LauncherSquareView(icon: widget.launcherIcon, badge: widget.launcherBadge) {
                    registry.requestTakeover(widget.id)
                }
            }
            LauncherSquareView(icon: "gearshape", badge: nil) {
                SettingsWindowController.shared.show(registry: registry)
            }
            Spacer(minLength: 0)
        }
    }
}

// inputs {icon, badge, action}, does {one 30pt launcher square with hover highlight and optional count badge}, returns {View}
struct LauncherSquareView: View {
    let icon: String
    let badge: String?
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(hovered ? 0.95 : 0.65))
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(hovered ? 0.16 : 0.07)))
                .overlay(alignment: .topTrailing) {
                    if let badge {
                        Text(badge)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(Circle().fill(.blue))
                            .offset(x: 5, y: -5)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// inputs {widget}, does {uniform card chrome around a widget's expandedView}, returns {View}
struct WidgetCardView: View {
    let widget: NotchWidget

    var body: some View {
        widget.expandedView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.07))
            )
            // A widget whose min content width exceeds its share must never paint over the neighbor card.
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// inputs {targetId, draggedId, registry}, does {reorders widgets live while dragging over targets}, returns {DropDelegate}
struct WidgetReorderDelegate: DropDelegate {
    let targetId: String
    @Binding var draggedId: String?
    let registry: WidgetRegistry

    func dropEntered(info: DropInfo) {
        guard let draggedId else { return }
        registry.move(draggedId, before: targetId)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedId = nil
        return true
    }
}
