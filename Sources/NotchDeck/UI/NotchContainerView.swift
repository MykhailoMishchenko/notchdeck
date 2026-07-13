import SwiftUI

// inputs {expanded flag}, does {shared hover/expand state between AppKit controller and SwiftUI}, returns {observable}
final class NotchState: ObservableObject {
    @Published var expanded = false {
        didSet {
            if expanded != oldValue { Log.info("state: \(expanded ? "expanded" : "collapsed")") }
        }
    }
    private var collapseWork: DispatchWorkItem?
    /// Set by the controller: is the REAL cursor currently inside the interactive zone (screen coords).
    /// Hover events are noisy while the shape animates; cursor position is the source of truth.
    var isCursorInZone: () -> Bool = { false }

    // inputs {hovering}, does {expands immediately on hover-in; on hover-out collapses after a grace delay, but only if the cursor really left the zone}, returns {}
    func setHovering(_ hovering: Bool) {
        Log.info("hover event: \(hovering) cursorInZone=\(isCursorInZone()) expanded=\(expanded)")
        collapseWork?.cancel()
        if hovering {
            expanded = true
        } else {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let inZone = self.isCursorInZone()
                Log.info("collapse check: cursorInZone=\(inZone)")
                guard !inZone else { return }
                self.expanded = false
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
    }
}

// inputs {state, geometry, hasNotch, expandedSize}, does {renders collapsed notch/pill and hover-expanded panel with spring animation}, returns {View}
struct NotchContainerView: View {
    @ObservedObject var state: NotchState
    let hasNotch: Bool
    let geometry: NotchGeometry
    let expandedSize: CGSize

    private var collapsedWidth: CGFloat { geometry.notchWidth + geometry.topCornerRadius * 2 }
    private var collapsedHeight: CGFloat { geometry.notchHeight }
    private var currentWidth: CGFloat { state.expanded ? expandedSize.width : collapsedWidth }
    private var currentHeight: CGFloat { state.expanded ? expandedSize.height : collapsedHeight }
    private var bottomRadius: CGFloat { state.expanded ? 24 : geometry.bottomCornerRadius }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchShape(topCornerRadius: geometry.topCornerRadius, bottomCornerRadius: bottomRadius)
                    .fill(Color.black)
                if state.expanded {
                    expandedContent
                        .padding(.top, geometry.notchHeight)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                        .transition(.asymmetric(
                            insertion: .opacity.animation(.easeOut(duration: 0.15).delay(0.15)),
                            removal: .opacity.animation(.easeIn(duration: 0.08))
                        ))
                }
            }
            .frame(width: currentWidth, height: currentHeight)
            .clipShape(NotchShape(topCornerRadius: geometry.topCornerRadius, bottomCornerRadius: bottomRadius))
            .contentShape(Rectangle())
            .onHover { state.setHovering($0) }
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: state.expanded)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: hasNotch ? "macbook" : "display")
                    .foregroundStyle(.white.opacity(0.8))
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
            Text("Этап 1 — каркас окна. Здесь появятся виджеты.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.6))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
