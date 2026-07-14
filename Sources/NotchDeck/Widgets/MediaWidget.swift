import AppKit
import SwiftUI

// inputs {}, does {observable now-playing state shared between the widget and its views}, returns {model}
final class MediaModel: ObservableObject {
    @Published var track = ""
    @Published var artist = ""
    @Published var isPlaying = false
    @Published var source: String?
    @Published var pickerVisible = false
    @Published var loadingPlaylists = false
    @Published var playlists: [String] = []
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
        AnyView(MediaCardView(
            model: model,
            onCommand: { [weak self] command in self?.control(command) },
            onTogglePicker: { [weak self] in self?.togglePicker() },
            onPlayPlaylist: { [weak self] name in self?.play(playlist: name) }
        ))
    }

    func onAppear() {
        refreshFromRunningPlayer()
    }

    // inputs {notification}, does {push update: applies track/artist/state from the player's broadcast; hides the playlist picker once something plays}, returns {}
    @objc private func playbackChanged(_ notification: Notification) {
        let info = notification.userInfo
        DispatchQueue.main.async { [self] in
            model.source = notification.name.rawValue.contains("spotify") ? "Spotify" : "Music"
            model.track = info?["Name"] as? String ?? ""
            model.artist = info?["Artist"] as? String ?? ""
            model.isPlaying = (info?["Player State"] as? String) == "Playing"
            if model.isPlaying { model.pickerVisible = false }
            Log.info("media push: \(model.source ?? "?") \(model.isPlaying ? "playing" : "paused") \(model.track)")
        }
    }

    // inputs {}, does {shows/hides the Apple Music playlist picker; loads playlist names on first open}, returns {}
    private func togglePicker() {
        if model.pickerVisible {
            model.pickerVisible = false
            return
        }
        model.pickerVisible = true
        model.loadingPlaylists = true
        let script = """
        tell application "Music"
            set playlistNames to name of user playlists
        end tell
        set AppleScript's text item delimiters to linefeed
        return playlistNames as string
        """
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.runScript(script)
            let names = (result ?? "")
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            DispatchQueue.main.async {
                self.model.playlists = names
                self.model.loadingPlaylists = false
                Log.info("media: loaded \(names.count) playlists")
            }
        }
    }

    // inputs {playlist name}, does {starts the Apple Music playlist; the resulting playerInfo push flips the card to now-playing}, returns {}
    private func play(playlist: String) {
        let escaped = playlist
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.runScript("tell application \"Music\" to play user playlist \"\(escaped)\"")
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

// inputs {model, callbacks}, does {media card UI: now-playing controls, idle state, Apple Music playlist picker}, returns {View}
struct MediaCardView: View {
    @ObservedObject var model: MediaModel
    let onCommand: (String) -> Void
    let onTogglePicker: () -> Void
    let onPlayPlaylist: (String) -> Void

    var body: some View {
        Group {
            if model.pickerVisible {
                picker
            } else if model.track.isEmpty {
                idle
            } else {
                nowPlaying
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var idle: some View {
        Button(action: onTogglePicker) {
            VStack(spacing: 6) {
                Image(systemName: "music.note.list")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.4))
                Text("Choose a playlist")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Button(action: onTogglePicker) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                Text("Playlists")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            if model.loadingPlaylists {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.playlists.isEmpty {
                Text("No playlists")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(model.playlists, id: \.self) { name in
                            Button { onPlayPlaylist(name) } label: {
                                Text(name)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.85))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 2)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var nowPlaying: some View {
        VStack(spacing: 8) {
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

    private func controlButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.85))
        }
        .buttonStyle(.plain)
    }
}
