import Foundation
import SwiftUI

// inputs {}, does {observable Claude plan-limits state (mirrors Claude Code's /usage screen)}, returns {model}
final class ClaudeUsageModel: ObservableObject {
    struct Limit: Identifiable {
        let id: String
        let title: String
        let percent: Double
        let resets: String
    }

    @Published var connected = ClaudeAuth.isConnected
    @Published var plan: String? = ClaudeAuth.plan
    @Published var limits: [Limit] = []
    @Published var status = "Loading…"
}

// inputs {}, does {Claude limits widget: the REAL plan limits (session / weekly / per-model) from Anthropic's OAuth usage endpoint using the local Claude Code token; crab placeholder until connected via Settings}, returns {NotchWidget}
final class ClaudeUsageWidget: NotchWidget {
    let id = "claude"
    let displayName = "Claude"
    let updateInterval: TimeInterval? = 60

    private let model = ClaudeUsageModel()
    private let crab = CrabAnimationModel()
    private var fetching = false
    private weak var host: WidgetHost?
    private var crabTimer: Timer?

    init() {
        scheduleCrab(after: 45)
    }

    func attach(host: WidgetHost) {
        self.host = host
    }

    // inputs {delay}, does {every few minutes, if the island is idle (no music/timer accessories), lets the crab run out and wave}, returns {}
    private func scheduleCrab(after delay: TimeInterval) {
        crabTimer?.invalidate()
        crabTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            let islandBusy = (self.host?.collapsedAccessoryWidthExcluding(self.id) ?? 0) > 0
            if !islandBusy {
                self.crab.play()
            }
            self.scheduleCrab(after: TimeInterval(Int.random(in: 150...300)))
        }
    }

    var expandedWidthWeight: CGFloat { 0 }
    var launcherIcon: String { "sparkles" }
    var launcherBadge: String? { nil }

    var expandedView: AnyView { AnyView(EmptyView()) }

    var takeoverView: AnyView {
        AnyView(ClaudeUsageTakeoverView(model: model))
    }

    var collapsedTrailing: AnyView { AnyView(CrabRunView(model: crab)) }
    var collapsedAccessoryWidth: CGFloat { crab.slotWidth }

    // inputs {}, does {poll tick: reads the token on demand (never stored) and fetches /api/oauth/usage off-main}, returns {}
    func refresh() {
        model.connected = ClaudeAuth.isConnected
        model.plan = ClaudeAuth.plan
        guard model.connected, !fetching else { return }
        fetching = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            defer { self?.fetching = false }
            guard let token = ClaudeAuth.accessToken() else {
                DispatchQueue.main.async { self?.model.status = "Credentials unavailable — reconnect in Settings" }
                return
            }
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            let semaphore = DispatchSemaphore(value: 0)
            var payload: Data?
            var statusCode = 0
            URLSession.shared.dataTask(with: request) { data, response, _ in
                statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                if statusCode == 200 { payload = data }
                semaphore.signal()
            }.resume()
            _ = semaphore.wait(timeout: .now() + 15)
            guard let payload else {
                if statusCode == 401 { ClaudeAuth.invalidateCache() }
                DispatchQueue.main.async { self?.model.status = "Usage request failed — token may be expired" }
                return
            }
            self?.parse(payload)
        }
    }

    // inputs {json}, does {maps the `limits` array to display rows exactly like Claude's /usage screen}, returns {}
    private func parse(_ data: Data) {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rawLimits = root["limits"] as? [[String: Any]]
        else {
            DispatchQueue.main.async { [model] in model.status = "Unexpected usage response" }
            return
        }
        let limits = rawLimits.compactMap { entry -> ClaudeUsageModel.Limit? in
            guard let kind = entry["kind"] as? String,
                  let percent = entry["percent"] as? Double else { return nil }
            let title: String
            switch kind {
            case "session": title = "Current session"
            case "weekly_all": title = "All models"
            default:
                let scope = entry["scope"] as? [String: Any]
                let modelInfo = scope?["model"] as? [String: Any]
                title = modelInfo?["display_name"] as? String ?? "Model"
            }
            return ClaudeUsageModel.Limit(
                id: kind + title,
                title: title,
                percent: percent,
                resets: Self.resetText(entry["resets_at"] as? String, session: kind == "session")
            )
        }
        DispatchQueue.main.async { [model] in
            model.limits = limits
            model.status = limits.isEmpty ? "No limit data" : ""
        }
    }

    // inputs {iso date, session flag}, does {session -> "in 4h 9m", weekly -> "Tue 1:00 PM"}, returns {string}
    private static func resetText(_ iso: String?, session: Bool) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let iso, let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
        if session {
            let minutes = max(0, Int(date.timeIntervalSinceNow / 60))
            return "resets in \(minutes / 60)h \(minutes % 60)m"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"
        return "resets \(formatter.string(from: date))"
    }
}

// inputs {model}, does {Claude limits UI: plan header + progress rows, or the pixel crab when not connected}, returns {View}
struct ClaudeUsageTakeoverView: View {
    @ObservedObject var model: ClaudeUsageModel

    var body: some View {
        Group {
            if !model.connected {
                VStack(spacing: 8) {
                    ClaudePixelCrabView()
                        .frame(width: 64, height: 44)
                    Text("Connect Claude in Settings")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.limits.isEmpty {
                Text(model.status)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Text("Plan usage limits")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                        if let plan = model.plan {
                            Text(plan)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer()
                    }
                    ForEach(model.limits) { limit in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(limit.title)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.85))
                                Text(limit.resets)
                                    .font(.system(size: 8))
                                    .foregroundStyle(.white.opacity(0.4))
                                Spacer()
                                Text("\(Int(limit.percent))%")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(limit.percent > 80 ? .orange : .white.opacity(0.7))
                            }
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(.white.opacity(0.1))
                                    Capsule()
                                        .fill(limit.percent > 80 ? Color.orange : Color.blue)
                                        .frame(width: max(4, proxy.size.width * limit.percent / 100))
                                }
                            }
                            .frame(height: 4)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
