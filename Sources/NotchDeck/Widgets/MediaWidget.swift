import AppKit
import SwiftUI

// inputs {}, does {one playlist entry with a stable Music persistent ID (names can duplicate)}, returns {value}
struct PlaylistItem: Identifiable {
    let id: String
    let name: String
}

// inputs {}, does {observable now-playing state shared between the widget and its views}, returns {model}
final class MediaModel: ObservableObject {
    @Published var track = ""
    @Published var artist = ""
    @Published var album = ""
    @Published var isPlaying = false
    @Published var source: String?
    @Published var artwork: NSImage?
    @Published var islandVisible = false
    @Published var pickerVisible = false
    @Published var loadingPlaylists = false
    @Published var playlists: [PlaylistItem] = []

    var hasTrack: Bool { !track.isEmpty }
}

// inputs {}, does {push-based media widget: track/state via DistributedNotificationCenter (Spotify + Apple Music), artwork fetch, playlist picker, controls via AppleScript}, returns {NotchWidget}
final class MediaWidget: NotchWidget {
    let id = "media"
    let displayName = "Media"
    private let model = MediaModel()
    private var artworkKey = ""
    private var hideIslandWork: DispatchWorkItem?

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
            onPlayPlaylist: { [weak self] playlistID in self?.play(playlistID: playlistID) }
        ))
    }

    var collapsedLeading: AnyView { AnyView(MediaCollapsedArtView(model: model)) }
    var collapsedTrailing: AnyView { AnyView(MediaCollapsedBarsView(model: model)) }
    var collapsedAccessoryWidth: CGFloat { model.islandVisible ? 72 : 0 }
    var expandedWidthWeight: CGFloat { 1.7 }

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
            updateIslandVisibility()
        }
    }

    // inputs {}, does {island shows while playing; on pause it stays for 60s then hides; resume cancels the hide}, returns {}
    private func updateIslandVisibility() {
        hideIslandWork?.cancel()
        hideIslandWork = nil
        guard model.hasTrack else {
            model.islandVisible = false
            return
        }
        model.islandVisible = true
        guard !model.isPlaying else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.model.islandVisible = false
            Log.info("media: island hidden after 60s pause")
        }
        hideIslandWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: work)
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
            set out to ""
            repeat with p in user playlists
                set out to out & (persistent ID of p) & tab & (name of p) & linefeed
            end repeat
            return out
        end tell
        """
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.runScript(script)?.stringValue
            let items = (result ?? "")
                .components(separatedBy: "\n")
                .compactMap { line -> PlaylistItem? in
                    let parts = line.components(separatedBy: "\t")
                    guard parts.count == 2 else { return nil }
                    let name = parts[1].trimmingCharacters(in: .whitespaces)
                    guard !parts[0].isEmpty, !name.isEmpty else { return nil }
                    return PlaylistItem(id: parts[0], name: name)
                }
            DispatchQueue.main.async {
                self.model.playlists = items
                self.model.loadingPlaylists = false
                Log.info("media: loaded \(items.count) playlists")
            }
        }
    }

    // inputs {playlist persistent ID}, does {starts the exact Apple Music playlist (names can duplicate); the resulting playerInfo push flips the card to now-playing}, returns {}
    private func play(playlistID: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.runScript(
                "tell application \"Music\" to play (first user playlist whose persistent ID is \"\(playlistID)\")"
            )
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
                self.updateIslandVisibility()
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
