import Foundation
import SwiftUI

// inputs {}, does {observable Claude usage state (active 5h block via ccusage)}, returns {model}
final class ClaudeUsageModel: ObservableObject {
    @Published var cost: String?
    @Published var tokens: String?
    @Published var burnRate: String?
    @Published var projectedCost: String?
    @Published var resetsIn: String?
    @Published var status = "Loading…"
}

// inputs {}, does {Claude limits widget: polls `ccusage blocks --active --json` every 60s while visible and shows the active block's cost/tokens/burn/reset}, returns {NotchWidget}
final class ClaudeUsageWidget: NotchWidget {
    let id = "claude"
    let displayName = "Claude"
    let updateInterval: TimeInterval? = 60

    private let model = ClaudeUsageModel()
    private static let ccusageURL: URL? = locateCcusage()
    private var fetching = false

    var expandedWidthWeight: CGFloat { 0 }
    var launcherIcon: String { "sparkles" }
    var launcherBadge: String? { nil }

    var expandedView: AnyView { AnyView(EmptyView()) }

    var takeoverView: AnyView {
        AnyView(ClaudeUsageTakeoverView(model: model))
    }

    // inputs {}, does {poll tick: runs ccusage off-main and publishes the parsed block}, returns {}
    func refresh() {
        guard let ccusage = Self.ccusageURL else {
            model.status = "ccusage not found"
            return
        }
        guard !fetching else { return }
        fetching = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            defer { self?.fetching = false }
            let process = Process()
            process.executableURL = ccusage
            process.arguments = ["blocks", "--active", "--json"]
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = ccusage.deletingLastPathComponent().path + ":/usr/bin:/bin"
            process.environment = environment
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
            } catch {
                DispatchQueue.main.async { self?.model.status = "ccusage failed" }
                return
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            self?.parse(data)
        }
    }

    // inputs {json data}, does {extracts the active block and publishes formatted fields}, returns {}
    private func parse(_ data: Data) {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let blocks = root["blocks"] as? [[String: Any]],
            let block = blocks.first(where: { $0["isActive"] as? Bool == true }) ?? blocks.first
        else {
            DispatchQueue.main.async { [model] in
                model.status = "No active block"
                model.cost = nil
            }
            return
        }

        let cost = (block["costUSD"] as? Double).map { String(format: "$%.2f", $0) }
        var tokens: String?
        if let counts = block["tokenCounts"] as? [String: Any] {
            let total = counts.values.compactMap { $0 as? Double }.reduce(0, +)
            tokens = Self.compactNumber(total)
        }
        var burn: String?
        if let burnRate = block["burnRate"] as? [String: Any],
           let perHour = burnRate["costPerHour"] as? Double {
            burn = String(format: "$%.0f/h", perHour)
        }
        var projected: String?
        if let projection = block["projection"] as? [String: Any],
           let total = projection["totalCost"] as? Double {
            projected = String(format: "$%.0f", total)
        }
        var resets: String?
        if let endString = block["endTime"] as? String,
           let end = ISO8601DateFormatter().date(from: endString) {
            let minutes = max(0, Int(end.timeIntervalSinceNow / 60))
            resets = String(format: "%d:%02d", minutes / 60, minutes % 60)
        }

        DispatchQueue.main.async { [model] in
            model.cost = cost
            model.tokens = tokens
            model.burnRate = burn
            model.projectedCost = projected
            model.resetsIn = resets
            model.status = "Active block"
        }
    }

    // inputs {}, does {finds a ccusage binary: brew paths, then newest nvm node}, returns {url or nil}
    private static func locateCcusage() -> URL? {
        let fm = FileManager.default
        var candidates = ["/opt/homebrew/bin/ccusage", "/usr/local/bin/ccusage"]
        let nvmRoot = NSHomeDirectory() + "/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvmRoot) {
            let sorted = versions.sorted { lhs, rhs in
                lhs.compare(rhs, options: .numeric) == .orderedDescending
            }
            candidates.append(contentsOf: sorted.map { "\(nvmRoot)/\($0)/bin/ccusage" })
        }
        return candidates.first(where: fm.isExecutableFile(atPath:)).map(URL.init(fileURLWithPath:))
    }

    // inputs {value}, does {formats 233315060 -> "233.3M"}, returns {string}
    private static func compactNumber(_ value: Double) -> String {
        switch value {
        case 1_000_000...: return String(format: "%.1fM", value / 1_000_000)
        case 1_000...: return String(format: "%.1fK", value / 1_000)
        default: return String(Int(value))
        }
    }
}

// inputs {model}, does {Claude usage takeover UI: cost, tokens, burn rate, projection, reset countdown}, returns {View}
struct ClaudeUsageTakeoverView: View {
    @ObservedObject var model: ClaudeUsageModel

    var body: some View {
        Group {
            if let cost = model.cost {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(cost)
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white)
                        Text("current block")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.45))
                        Spacer()
                        if let resets = model.resetsIn {
                            statRow("resets in", resets)
                        }
                    }
                    HStack(spacing: 14) {
                        if let tokens = model.tokens { statRow("tokens", tokens) }
                        if let burn = model.burnRate { statRow("burn", burn) }
                        if let projected = model.projectedCost { statRow("projected", projected) }
                        Spacer()
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.4))
                    Text(model.status)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.4))
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}
