import AppKit
import SwiftUI

// inputs {}, does {observable countdown state}, returns {model}
final class TimerModel: ObservableObject {
    @Published var selectedMinutes = 25
    @Published var remaining = 0
    @Published var running = false
    @Published var finished = false

    var total: Int { selectedMinutes * 60 }
    var active: Bool { running || finished }
    var progress: Double {
        guard total > 0 else { return 0 }
        return 1 - Double(remaining) / Double(total)
    }
}

// inputs {}, does {timer widget: presets + start/pause/reset in the takeover; while running the island shows an orange progress ring (left) and the remaining time (right), iOS style}, returns {NotchWidget}
final class TimerWidget: NotchWidget {
    let id = "timer"
    let displayName = "Timer"

    private let model = TimerModel()
    private var tick: Timer?

    var expandedWidthWeight: CGFloat { 0 }
    var launcherIcon: String { "timer" }
    var launcherBadge: String? { nil }

    var expandedView: AnyView { AnyView(EmptyView()) }
    var takeoverView: AnyView {
        AnyView(TimerTakeoverView(
            model: model,
            onStartPause: { [weak self] in self?.startPause() },
            onReset: { [weak self] in self?.reset() }
        ))
    }

    var collapsedLeading: AnyView { AnyView(TimerCollapsedRingView(model: model)) }
    var collapsedTrailing: AnyView { AnyView(TimerCollapsedTextView(model: model)) }
    var collapsedAccessoryWidth: CGFloat { model.active ? 84 : 0 }

    // inputs {}, does {start/resume or pause; the tick runs independently of panel visibility}, returns {}
    private func startPause() {
        if model.running {
            model.running = false
            tick?.invalidate()
            return
        }
        if model.remaining == 0 { model.remaining = model.total }
        model.finished = false
        model.running = true
        tick?.invalidate()
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.step()
        }
    }

    private func step() {
        guard model.remaining > 0 else { return }
        model.remaining -= 1
        if model.remaining == 0 {
            model.running = false
            tick?.invalidate()
            model.finished = true
            NSSound(named: "Glass")?.play()
            Log.info("timer: finished")
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                if self?.model.finished == true { self?.reset() }
            }
        }
    }

    private func reset() {
        tick?.invalidate()
        model.running = false
        model.finished = false
        model.remaining = 0
    }
}

// inputs {model}, does {island left slot: orange progress ring while the timer is active}, returns {View}
struct TimerCollapsedRingView: View {
    @ObservedObject var model: TimerModel

    var body: some View {
        Group {
            if model.active {
                ZStack {
                    Circle()
                        .stroke(.orange.opacity(0.3), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: max(0.02, model.progress))
                        .stroke(.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 15, height: 15)
                .padding(.leading, 11)
                .padding(.trailing, 6)
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.active)
    }
}

// inputs {model}, does {island right slot: remaining time in orange ("27 мин" / "45 с" / "Готово")}, returns {View}
struct TimerCollapsedTextView: View {
    @ObservedObject var model: TimerModel

    var body: some View {
        Group {
            if model.active {
                Text(label)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .padding(.leading, 6)
                    .padding(.trailing, 12)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.active)
    }

    private var label: String {
        if model.finished { return "Готово" }
        if model.remaining >= 60 { return "\(Int((Double(model.remaining) / 60).rounded(.up))) мин" }
        return "\(model.remaining) с"
    }
}

// inputs {model, callbacks}, does {timer takeover: preset chips, big countdown, start/pause/reset}, returns {View}
struct TimerTakeoverView: View {
    @ObservedObject var model: TimerModel
    let onStartPause: () -> Void
    let onReset: () -> Void

    private let presets = [5, 10, 15, 25, 45, 60]

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text(displayTime)
                    .font(.system(size: 30, weight: .bold).monospacedDigit())
                    .foregroundStyle(model.finished ? .orange : .white)
                HStack(spacing: 5) {
                    ForEach(presets, id: \.self) { minutes in
                        Button {
                            guard !model.running else { return }
                            model.selectedMinutes = minutes
                            model.remaining = 0
                            model.finished = false
                        } label: {
                            Text("\(minutes)")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(model.selectedMinutes == minutes ? .black : .white.opacity(0.7))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(model.selectedMinutes == minutes ? .orange : .white.opacity(0.08))
                                )
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .opacity(model.running ? 0.4 : 1)
                    }
                }
            }
            Spacer()
            HStack(spacing: 12) {
                Button(action: onStartPause) {
                    Image(systemName: model.running ? "pause.fill" : "play.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.black)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(.orange))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                Button(action: onReset) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(.white.opacity(0.08)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var displayTime: String {
        let seconds = model.remaining == 0 && !model.finished ? model.total : model.remaining
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
