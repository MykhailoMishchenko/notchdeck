import SwiftUI
import UniformTypeIdentifiers

// inputs {registry}, does {expanded panel content: header row + widget cards with drag&drop reorder}, returns {View}
struct WidgetPanelView: View {
    @ObservedObject var registry: WidgetRegistry
    @State private var draggedId: String?

    private let spacing: CGFloat = 10

    private let launcherWidth: CGFloat = 70

    var body: some View {
        if let takeoverId = registry.takeoverId,
           let widget = registry.activeWidgets.first(where: { $0.id == takeoverId }) {
            // Platform-provided exit for EVERY takeover: back chevron + right-swipe.
            widget.takeoverView
                .overlay(alignment: .topLeading) {
                    Button { registry.endTakeover() } label: {
                        Image(systemName: "chevron.backward.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                    .padding(2)
                }
                .gesture(
                    DragGesture(minimumDistance: 15)
                        .onEnded { value in
                            if value.translation.width > 40 { registry.endTakeover() }
                        }
                )
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

// inputs {widgets, registry}, does {two-column grid of small squares: weight-0 widgets (open their takeover) + Settings gear}, returns {View}
struct LauncherColumnView: View {
    let widgets: [NotchWidget]
    let registry: WidgetRegistry

    /// Plain rows of two, NOT LazyVGrid — lazy containers clip children, cutting corner badges.
    var body: some View {
        let entries = launcherEntries
        VStack(spacing: 6) {
            ForEach(Array(stride(from: 0, to: entries.count, by: 2)), id: \.self) { index in
                HStack(spacing: 6) {
                    launcherSquare(entries[index])
                    if index + 1 < entries.count {
                        launcherSquare(entries[index + 1])
                    } else {
                        Color.clear.frame(width: 30, height: 30)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private struct LauncherEntry {
        let id: String
        let icon: String
        let badge: String?
        let action: () -> Void
    }

    private var launcherEntries: [LauncherEntry] {
        var entries = widgets.map { widget in
            LauncherEntry(id: widget.id, icon: widget.launcherIcon, badge: widget.launcherBadge) {
                registry.requestTakeover(widget.id)
            }
        }
        entries.append(LauncherEntry(id: "__settings", icon: "gearshape", badge: nil) {
            SettingsWindowController.shared.show(registry: registry)
        })
        return entries
    }

    private func launcherSquare(_ entry: LauncherEntry) -> some View {
        LauncherSquareView(icon: entry.icon, badge: entry.badge, action: entry.action)
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
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(2.5)
                            .background(Circle().fill(.blue))
                            .offset(x: 3, y: -3)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        // Lift badge-carrying squares above grid siblings so the badge is never painted over.
        .zIndex(badge == nil ? 0 : 1)
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
