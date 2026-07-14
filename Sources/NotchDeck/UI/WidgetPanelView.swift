import SwiftUI
import UniformTypeIdentifiers

// inputs {registry}, does {expanded panel content: header row + widget cards with drag&drop reorder}, returns {View}
struct WidgetPanelView: View {
    @ObservedObject var registry: WidgetRegistry
    @State private var draggedId: String?

    private let spacing: CGFloat = 10

    var body: some View {
        if let takeoverId = registry.takeoverId,
           let widget = registry.widgets.first(where: { $0.id == takeoverId }) {
            widget.takeoverView
        } else {
            cardRow
        }
    }

    private var cardRow: some View {
        GeometryReader { proxy in
            let totalWeight = max(1, registry.widgets.map(\.expandedWidthWeight).reduce(0, +))
            let available = proxy.size.width - spacing * CGFloat(max(0, registry.widgets.count - 1))
            HStack(spacing: spacing) {
                ForEach(registry.widgets, id: \.id) { widget in
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
            }
        }
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
