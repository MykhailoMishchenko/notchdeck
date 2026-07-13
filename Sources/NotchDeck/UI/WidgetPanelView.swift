import SwiftUI
import UniformTypeIdentifiers

// inputs {registry}, does {expanded panel content: header row + widget cards with drag&drop reorder}, returns {View}
struct WidgetPanelView: View {
    @ObservedObject var registry: WidgetRegistry
    @State private var draggedId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            HStack(spacing: 10) {
                ForEach(registry.widgets, id: \.id) { widget in
                    WidgetCardView(widget: widget)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack {
            Text("NotchDeck")
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
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
