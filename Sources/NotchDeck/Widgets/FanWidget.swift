import NotchDeckShared
import SwiftUI

// inputs {}, does {observable fan/thermal state + control state}, returns {model}
final class FanModel: ObservableObject {
    struct Fan: Identifiable {
        let id: Int
        let rpm: Double
        let minRPM: Double
        let maxRPM: Double
    }

    @Published var fans: [Fan] = []
    @Published var cpuTemp: Double?
    @Published var gpuTemp: Double?
    @Published var unavailable = false
    /// nil = helper not reachable (control hidden); true/false = manual/auto.
    @Published var helperAvailable = false
    @Published var manual = false
    @Published var targets: [Int: Double] = [:]
}

// inputs {}, does {fan widget: RPM/temp monitor via user-space SMC reads + real CONTROL through the embedded privileged XPC helper (sliders + Auto), with the helper enforcing clamps and auto-revert}, returns {NotchWidget}
final class FanWidget: NotchWidget {
    let id = "fans"
    let displayName = "Fans"
    let updateInterval: TimeInterval? = 2

    private let model = FanModel()

    var expandedWidthWeight: CGFloat { 0 }
    var launcherIcon: String { "fanblades" }
    var launcherBadge: String? { nil }

    var expandedView: AnyView { AnyView(EmptyView()) }

    var takeoverView: AnyView {
        AnyView(FanTakeoverView(
            model: model,
            onSetAuto: { [weak self] in self?.setAuto() },
            onSetTarget: { [weak self] fan, rpm in self?.setTarget(fan: fan, rpm: rpm) }
        ))
    }

    // inputs {}, does {poll tick: reads fan count, per-fan actual/min/max RPM, cluster temperatures, and probes the helper}, returns {}
    func refresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let count = SMC.fanCount
            var fans: [FanModel.Fan] = []
            for index in 0..<count {
                guard let rpm = SMC.readValue("F\(index)Ac") else { continue }
                fans.append(FanModel.Fan(
                    id: index,
                    rpm: rpm,
                    minRPM: SMC.readValue("F\(index)Mn") ?? 0,
                    maxRPM: SMC.readValue("F\(index)Mx") ?? max(rpm, 1)
                ))
            }
            // M-series SMC exposes per-core sensors; average whatever this model has.
            let cpu = SMC.averageTemperature(["Tp01", "Tp05", "Tp09", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0T", "Tp0X", "Tp0b"])
            let gpu = SMC.averageTemperature(["Tg05", "Tg0D", "Tg0L", "Tg0T"])
            let modes = (0..<count).map { SMC.readValue("F\($0)Md") ?? 0 }
            DispatchQueue.main.async {
                self.model.fans = fans
                self.model.cpuTemp = cpu
                self.model.gpuTemp = gpu
                self.model.manual = modes.contains { $0 > 0 }
                self.model.unavailable = fans.isEmpty && cpu == nil && gpu == nil
                for fan in fans where self.model.targets[fan.id] == nil {
                    self.model.targets[fan.id] = fan.rpm
                }
            }
        }
        FanControlClient.shared.status { [weak self] ok, _ in
            DispatchQueue.main.async { self?.model.helperAvailable = ok }
        }
    }

    private func setAuto() {
        FanControlClient.shared.setMode(manual: false) { [weak self] ok in
            DispatchQueue.main.async {
                if ok { self?.model.manual = false }
                Log.info("fans: auto \(ok ? "ok" : "failed")")
            }
        }
    }

    private func setTarget(fan: Int, rpm: Double) {
        FanControlClient.shared.setTarget(fan: fan, rpm: rpm) { [weak self] ok in
            DispatchQueue.main.async {
                if ok { self?.model.manual = true }
                Log.info("fans: target \(Int(rpm)) for fan \(fan) \(ok ? "ok" : "failed")")
            }
        }
    }
}

// inputs {model, callbacks}, does {fan takeover UI: RPM bars + temps; when the helper is enabled — per-fan sliders and an Auto button}, returns {View}
struct FanTakeoverView: View {
    @ObservedObject var model: FanModel
    let onSetAuto: () -> Void
    let onSetTarget: (Int, Double) -> Void

    var body: some View {
        Group {
            if model.unavailable {
                VStack(spacing: 6) {
                    Image(systemName: "fanblades")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Sensors unavailable")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(model.fans) { fan in
                        fanRow(fan)
                    }
                    HStack(spacing: 10) {
                        if let cpu = model.cpuTemp { temperatureChip("cpu", cpu) }
                        if let gpu = model.gpuTemp { temperatureChip("gpu", gpu) }
                        Spacer()
                        controlTrailing
                    }
                    Spacer(minLength: 0)
                }
                .padding(.trailing, 16)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var controlTrailing: some View {
        if model.helperAvailable {
            Button(action: onSetAuto) {
                Text("Auto")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(model.manual ? .black : .white.opacity(0.5))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(model.manual ? Color.orange : Color.white.opacity(0.08)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Return fans to automatic control")
        } else {
            Text("Enable fan control in Settings")
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    private func fanRow(_ fan: FanModel.Fan) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Fan \(fan.id + 1)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                if model.manual {
                    Text("manual")
                        .font(.system(size: 8))
                        .foregroundStyle(.orange.opacity(0.8))
                }
                Spacer()
                Text("\(Int(fan.rpm)) RPM")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
            }
            if model.helperAvailable {
                Slider(
                    value: Binding(
                        get: { model.targets[fan.id] ?? fan.rpm },
                        set: { model.targets[fan.id] = $0 }
                    ),
                    in: fan.minRPM...max(fan.minRPM + 1, fan.maxRPM)
                ) { editing in
                    if !editing {
                        onSetTarget(fan.id, model.targets[fan.id] ?? fan.rpm)
                    }
                }
                .controlSize(.mini)
                .tint(.orange)
            } else {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.1))
                        Capsule()
                            .fill(.blue.opacity(0.8))
                            .frame(width: proxy.size.width * fillFraction(fan))
                    }
                }
                .frame(height: 5)
            }
        }
    }

    private func fillFraction(_ fan: FanModel.Fan) -> CGFloat {
        let range = max(fan.maxRPM - fan.minRPM, 1)
        return CGFloat(min(max((fan.rpm - fan.minRPM) / range, 0), 1))
    }

    private func temperatureChip(_ label: String, _ value: Double) -> some View {
        HStack(spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
            Text("\(Int(value))°")
                .font(.caption.monospacedDigit())
                .foregroundStyle(value > 85 ? .orange : .white.opacity(0.85))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(.white.opacity(0.08)))
    }
}
