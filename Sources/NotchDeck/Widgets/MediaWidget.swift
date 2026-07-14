import AppKit
import SwiftUI

// inputs {}, does {observable now-playing state shared between the widget and its views}, returns {model}
final class MediaModel: ObservableObject {
    @Published var track = ""
    @Published var artist = ""
    @Published var album = ""
    @Published var isPlaying = false
    @Published var source: String?
    @Published var artwork: NSImage?
    @Published var pickerVisible = false
    @Published var loadingPlaylists = false
    @Published var playlists: [String] = []

    var hasTrack: Bool { !track.isEmpty }
}

// inputs {}, does {push-based media widget: track/state via DistributedNotificationCenter (Spotify + Apple Music), artwork fetch, playlist picker, controls via AppleScript}, returns {NotchWidget}
final class MediaWidget: NotchWidget {
    let id = "media"
    let displayName = "Media"
    private let model = MediaModel()
    private var artworkKey = ""

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
        // Island must light up on launch when something is already playing — don't wait for the first expand.
        refreshFromRunningPlayer()
    }

    var expandedView: AnyView {
        AnyView(MediaCardView(
            model: model,
            onCommand: { [weak self] command in self?.control(command) },
            onTogglePicker: { [weak self] in self?.togglePicker() },
            onPlayPlaylist: { [weak self] name in self?.play(playlist: name) }
        ))
    }

    var collapsedLeading: AnyView { AnyView(MediaCollapsedArtView(model: model)) }
    var collapsedTrailing: AnyView { AnyView(MediaCollapsedBarsView(model: model)) }
    var collapsedAccessoryWidth: CGFloat { model.hasTrack ? 72 : 0 }
    var expandedWidthWeight: CGFloat { 2 }

    func onAppear() {
        refreshFromRunningPlayer()
    }

    // inputs {notification}, does {push update: applies track/artist/state, hides the picker once something plays, refetches artwork}, returns {}
    @objc private func playbackChanged(_ notification: Notification) {
        let info = notification.userInfo
        DispatchQueue.main.async { [self] in
            model.source = notification.name.rawValue.contains("spotify") ? "Spotify" : "Music"
            model.track = info?["Name"] as? String ?? ""
            model.artist = info?["Artist"] as? String ?? ""
            model.album = info?["Album"] as? String ?? ""
            model.isPlaying = (info?["Player State"] as? String) == "Playing"
            if model.isPlaying { model.pickerVisible = false }
            Log.info("media push: \(model.source ?? "?") \(model.isPlaying ? "playing" : "paused") \(model.track)")
            fetchArtwork()
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
            let result = self.runScript(script)?.stringValue
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

    // inputs {}, does {fetches cover art for the current track (Music: raw artwork data; Spotify: artwork url + download), deduped per track}, returns {}
    private func fetchArtwork() {
        guard model.hasTrack else {
            artworkKey = ""
            model.artwork = nil
            return
        }
        let key = "\(model.source ?? "")|\(model.track)|\(model.artist)"
        guard key != artworkKey else { return }
        artworkKey = key
        let source = model.source
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            var image: NSImage?
            if source == "Spotify" {
                if let urlString = self.runScript("tell application \"Spotify\" to get artwork url of current track")?.stringValue,
                   let url = URL(string: urlString),
                   let data = try? Data(contentsOf: url) {
                    image = NSImage(data: data)
                }
            } else if let data = self.runScript("tell application \"Music\" to get data of artwork 1 of current track")?.data {
                image = NSImage(data: data)
            }
            DispatchQueue.main.async {
                guard self.artworkKey == key else { return }
                self.model.artwork = image
                Log.info("media: artwork \(image == nil ? "missing" : "loaded") for \(self.model.track)")
            }
        }
    }

    // inputs {}, does {pulls initial state from a running player once (before the first push arrives), off the main thread}, returns {}
    private func refreshFromRunningPlayer() {
        guard model.track.isEmpty, let player = runningPlayer() else { return }
        let script = """
        tell application "\(player)"
            if player state is playing or player state is paused then
                return (player state as string) & "|" & (name of current track) & "|" & (artist of current track) & "|" & (album of current track)
            end if
            return ""
        end tell
        """
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, let result = self.runScript(script)?.stringValue, !result.isEmpty else { return }
            let parts = result.components(separatedBy: "|")
            guard parts.count == 4 else { return }
            DispatchQueue.main.async {
                self.model.source = player
                self.model.isPlaying = parts[0] == "playing"
                self.model.track = parts[1]
                self.model.artist = parts[2]
                self.model.album = parts[3]
                self.fetchArtwork()
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

    // inputs {source}, does {executes AppleScript}, returns {result descriptor or nil}
    @discardableResult
    private func runScript(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { Log.info("media script error: \(error)") }
        return result
    }
}
