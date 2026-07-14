import AppKit
import SwiftUI

// inputs {}, does {observable now-playing state shared between the widget and its views}, returns {model}
final class MediaModel: ObservableObject {
    @Published var track = ""
    @Published var artist = ""
    @Published var isPlaying = false
    @Published var source: String?
}

// inputs {}, does {push-based media widget: track/state via DistributedNotificationCenter (Spotify + Apple Music), controls via AppleScript}, returns {NotchWidget}
final class MediaWidget: NotchWidget {
    let id = "media"
    let displayName = "Media"
    private let model = MediaModel()

    init() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(
            self, selector: #selector(playbackChanged(_:)),
            name: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil
        )
        center.addObserver(
            self, selector: #selector(playbackChanged(_:)),
            name: Notification.Name("com.apple.Music.playerInfo"), object: nil
        )
    }

    var expandedView: AnyView {
        AnyView(MediaCardView(model: model) { [weak self] command in self?.control(command) })
    }

    func onAppear() {
        refreshFromRunningPlayer()
    }

    // inputs {notification}, does {push update: applies track/artist/state from the player's broadcast}, returns {}
    @objc private func playbackChanged(_ notification: Notification) {
        let info = notification.userInfo
        DispatchQueue.main.async { [self] in
            model.source = notification.name.rawValue.contains("spotify") ? "Spotify" : "Music"
            model.track = info?["Name"] as? String ?? ""
            model.artist = info?["Artist"] as? String ?? ""
            model.isPlaying = (info?["Player State"] as? String) == "Playing"
            Log.info("media push: \(model.source ?? "?") \(model.isPlaying ? "playing" : "paused") \(model.track)")
        }
    }

    // inputs {command: playpause|next track|previous track}, does {sends the command to the active player via AppleScript, off the main thread (Apple Events + TCC prompts block)}, returns {}
    private func control(_ command: String) {
        guard let player = model.source ?? runningPlayer() else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.runScript("tell application \"\(player)\" to \(command)")
        }
    }

    // inputs {}, does {pulls initial state from a running player once (before the first push arrives), off the main thread}, returns {}
    private func refreshFromRunningPlayer() {
        guard model.track.isEmpty, let player = runningPlayer() else { return }
        let script = """
        tell application "\(player)"
            if player state is playing or player state is paused then
                return (player state as string) & "|" & (name of current track) & "|" & (artist of current track)
            end if
            return ""
        end tell
        """
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, let result = self.runScript(script), !result.isEmpty else { return }
            let parts = result.components(separatedBy: "|")
            guard parts.count == 3 else { return }
            DispatchQueue.main.async {
                self.model.source = player
                self.model.isPlaying = parts[0] == "playing"
                self.model.track = parts[1]
                self.model.artist = parts[2]
            }
        }
    }

    // inputs {}, does {finds a running supported player}, returns {app name or nil}
    private func runningPlayer() -> String? {
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        if running.contains("com.spotify.client") { return "Spotify" }
        if running.contains("com.apple.Music") { return "Music" }
        return nil
    }

    // inputs {source}, does {executes AppleScript}, returns {string result or nil}
    @discardableResult
    private func runScript(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { Log.info("media script error: \(error)") }
        return result?.stringValue
    }
}

// inputs {model, onCommand}, does {media card UI: track, artist, transport controls}, returns {View}
struct MediaCardView: View {
    @ObservedObject var model: MediaModel
    let onCommand: (String) -> Void

    var body: some View {
        VStack(spacing: 8) {
            if model.track.isEmpty {
                Image(systemName: "music.note")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.4))
                Text("Nothing playing")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                Text(model.track)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(model.artist)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                HStack(spacing: 14) {
                    controlButton("backward.fill") { onCommand("previous track") }
                    controlButton(model.isPlaying ? "pause.fill" : "play.fill") { onCommand("playpause") }
                    controlButton("forward.fill") { onCommand("next track") }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func controlButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.85))
        }
        .buttonStyle(.plain)
    }
}
