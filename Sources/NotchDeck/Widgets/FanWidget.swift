import SwiftUI

// inputs {}, does {observable fan/thermal state}, returns {model}
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
}

// inputs {}, does {fan monitor widget: RPM per fan + CPU/GPU temps via user-space SMC reads, 2s poll while visible. CONTROL will arrive later through the privileged XPC helper (separate project) — this widget is the platform's designated mount point for it}, returns {NotchWidget}
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
        AnyView(FanTakeoverView(model: model))
    }

    // inputs {}, does {poll tick: reads fan count, per-fan actual/min/max RPM and cluster temperatures}, returns {}
    func refresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let count = Int(SMC.readValue("FNum") ?? 0)
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
            DispatchQueue.main.async {
                self.model.fans = fans
                self.model.cpuTemp = cpu
                self.model.gpuTemp = gpu
                self.model.unavailable = fans.isEmpty && cpu == nil && gpu == nil
            }
        }
    }
}

// inputs {model}, does {fan takeover UI: RPM bars per fan + temperature chips; read-only until the XPC helper lands}, returns {View}
struct FanTakeoverView: View {
    @ObservedObject var model: FanModel

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
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.fans) { fan in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("Fan \(fan.id + 1)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                Spacer()
                                Text("\(Int(fan.rpm)) RPM")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.7))
                            }
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
                    HStack(spacing: 10) {
                        if let cpu = model.cpuTemp { temperatureChip("cpu", cpu) }
                        if let gpu = model.gpuTemp { temperatureChip("gpu", gpu) }
                        Spacer()
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
