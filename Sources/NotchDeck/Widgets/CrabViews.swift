import SwiftUI

// inputs {}, does {state machine for the idle-island easter egg: crab pushes the wall out, waves, runs away with dust}, returns {observable}
final class CrabAnimationModel: ObservableObject {
    enum Phase {
        case hidden, entering, waving, leaving
    }

    @Published var phase: Phase = .hidden
    @Published var armRaised = false

    var slotWidth: CGFloat { phase == .hidden ? 0 : 52 }

    private var waveTimer: Timer?

    // inputs {}, does {plays the full sequence once (~4s): push out -> wave 4 times -> run away}, returns {}
    func play() {
        guard phase == .hidden else { return }
        phase = .entering
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            guard let self else { return }
            self.phase = .waving
            var waves = 0
            self.waveTimer = Timer.scheduledTimer(withTimeInterval: 0.28, repeats: true) { [weak self] timer in
                guard let self else { return timer.invalidate() }
                self.armRaised.toggle()
                waves += 1
                if waves >= 6 {
                    timer.invalidate()
                    self.armRaised = false
                    self.phase = .leaving
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
                        self?.phase = .hidden
                    }
                }
            }
        }
    }
}

// inputs {model}, does {renders the crab run: slot grows (pushing the wall), wave frames, run-off with dust puffs}, returns {View}
struct CrabRunView: View {
    @ObservedObject var model: CrabAnimationModel

    var body: some View {
        Group {
            if model.phase != .hidden {
                ZStack(alignment: .bottomLeading) {
                    if model.phase == .leaving {
                        DustPuffsView()
                            .offset(x: 24, y: -5)
                    }
                    ClaudePixelCrabView(armRaised: model.armRaised)
                        .frame(width: 32, height: 21)
                        // Runs back LEFT — home under the physical notch; dust puffs stay behind him.
                        .offset(x: model.phase == .leaving ? -70 : 5)
                        .animation(.easeIn(duration: 0.7), value: model.phase == .leaving)
                        .padding(.bottom, 4)
                }
                .frame(width: model.slotWidth, alignment: .bottomLeading)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .clipped()
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.62), value: model.slotWidth)
    }
}

// inputs {}, does {three little dust puffs kicked up under the crab's feet as it runs off}, returns {View}
struct DustPuffsView: View {
    @State private var kicked = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(.white.opacity(0.45))
                    .frame(width: 4 + CGFloat(index), height: 4 + CGFloat(index))
                    .scaleEffect(kicked ? 1.6 : 0.3)
                    .opacity(kicked ? 0 : 0.8)
                    .animation(.easeOut(duration: 0.6).delay(Double(index) * 0.08), value: kicked)
            }
        }
        .onAppear { kicked = true }
    }
}

// inputs {armRaised}, does {Claude's pixel crab mascot in brand orange; right arm can wave}, returns {View}
struct ClaudePixelCrabView: View {
    var armRaised = false

    private static let orange = Color(red: 0.85, green: 0.47, blue: 0.34)

    // 14 x 8 pixel grid: 0 empty, 1 body
    private static let base: [[Int]] = [
        [0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 1, 0, 0, 0],
        [0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0],
        [0, 0, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1, 0, 0],
        [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
        [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
        [0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
        [0, 0, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 0, 0],
        [0, 0, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 0, 0],
    ]

    // Same crab with the right arm thrown up (wave frame).
    private static let waving: [[Int]] = [
        [0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 1, 0, 1, 1],
        [0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1],
        [0, 0, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1, 1, 0],
        [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
        [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
        [0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
        [0, 0, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 0, 0],
        [0, 0, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 0, 0],
    ]

    var body: some View {
        GeometryReader { proxy in
            let grid = armRaised ? Self.waving : Self.base
            // Snap cells to device pixels (0.5pt at 2x) — fractional coordinates antialias pixel art into mush.
            let rawCell = min(proxy.size.width / CGFloat(grid[0].count), proxy.size.height / CGFloat(grid.count))
            let cell = max(0.5, (rawCell * 2).rounded(.down) / 2)
            let xOffset = ((proxy.size.width - cell * CGFloat(grid[0].count)) / 2 * 2).rounded() / 2
            let yOffset = ((proxy.size.height - cell * CGFloat(grid.count)) * 2).rounded() / 2
            Canvas { context, _ in
                for (rowIndex, row) in grid.enumerated() {
                    for (columnIndex, value) in row.enumerated() where value == 1 {
                        context.fill(
                            Path(CGRect(
                                x: xOffset + CGFloat(columnIndex) * cell,
                                y: yOffset + CGFloat(rowIndex) * cell,
                                width: cell,
                                height: cell
                            )),
                            with: .color(Self.orange)
                        )
                    }
                }
            }
        }
    }
}
