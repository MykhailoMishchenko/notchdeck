import AppKit
import SwiftUI

// inputs {model, callbacks}, does {media card UI: idle -> picker (swipe-right back) -> artwork with overlay controls}, returns {View}
struct MediaCardView: View {
    @ObservedObject var model: MediaModel
    let onCommand: (String) -> Void
    let onTogglePicker: () -> Void
    let onPlayPlaylist: (String) -> Void

    var body: some View {
        Group {
            if model.pickerVisible {
                picker
            } else if model.hasTrack {
                nowPlaying
            } else {
                idle
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
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

    /// Back navigation: swipe right anywhere, or the single chevron icon.
    private var picker: some View {
        Group {
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
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(model.playlists, id: \.self) { name in
                            PlaylistRowView(name: name) { onPlayPlaylist(name) }
                        }
                    }
                    .padding(.top, 20)
                    .padding(.horizontal, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            Button(action: onTogglePicker) {
                Image(systemName: "chevron.backward.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .buttonStyle(.plain)
            .padding(6)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 15)
                .onEnded { value in
                    if value.translation.width > 40 { onTogglePicker() }
                }
        )
    }

    /// Reference layout: big art with a source badge on the left; title / album / artist and transport on the right.
    private var nowPlaying: some View {
        HStack(alignment: .center, spacing: 12) {
            artworkThumb
            VStack(alignment: .leading, spacing: 3) {
                Text(model.track)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(model.album)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                Text(model.artist)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
                HStack(spacing: 14) {
                    controlButton("backward.end.fill") { onCommand("previous track") }
                    controlButton(model.isPlaying ? "pause.fill" : "play.fill") { onCommand("playpause") }
                    controlButton("forward.end.fill") { onCommand("next track") }
                }
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var artworkThumb: some View {
        Group {
            if let artwork = model.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(0.1))
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.4))
                    )
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "music.note")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 19, height: 19)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(model.source == "Spotify"
                            ? Color(red: 0.11, green: 0.73, blue: 0.33)
                            : Color(red: 0.98, green: 0.18, blue: 0.28))
                )
                .offset(x: 4, y: 4)
        }
        .padding(.bottom, 4)
        .padding(.trailing, 4)
    }

    private func controlButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// inputs {name, onPlay}, does {one playlist row with hover highlight}, returns {View}
struct PlaylistRowView: View {
    let name: String
    let onPlay: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onPlay) {
            Text(name)
                .font(.caption2)
                .foregroundStyle(.white.opacity(hovered ? 1 : 0.8))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
                .padding(.horizontal, 5)
                .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(hovered ? 0.12 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// inputs {model}, does {Dynamic-Island left slot: album art thumbnail while a track is loaded}, returns {View}
struct MediaCollapsedArtView: View {
    @ObservedObject var model: MediaModel

    var body: some View {
        Group {
            if model.islandVisible {
                Group {
                    if let artwork = model.artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(.white.opacity(0.12))
                            .overlay(
                                Image(systemName: "music.note")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white.opacity(0.5))
                            )
                    }
                }
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .padding(.leading, 10)
                .padding(.trailing, 6)
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.islandVisible)
    }
}

// inputs {model}, does {Dynamic-Island right slot: equalizer bars, animated while playing}, returns {View}
struct MediaCollapsedBarsView: View {
    @ObservedObject var model: MediaModel

    var body: some View {
        Group {
            if model.islandVisible {
                EqualizerBarsView(animating: model.isPlaying)
                    .frame(width: 14, height: 14)
                    .padding(.leading, 6)
                    .padding(.trailing, 12)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.islandVisible)
    }
}

// inputs {animating}, does {three capsules bouncing at different speeds while playing, low static bars when paused}, returns {View}
struct EqualizerBarsView: View {
    let animating: Bool
    @State private var phase = false

    var body: some View {
        HStack(spacing: 2.5) {
            bar(high: 0.95, low: 0.35, speed: 0.34)
            bar(high: 0.55, low: 1.00, speed: 0.46)
            bar(high: 0.75, low: 0.45, speed: 0.38)
        }
        .onAppear { phase = true }
    }

    private func bar(high: CGFloat, low: CGFloat, speed: Double) -> some View {
        Capsule()
            .fill(.white.opacity(0.9))
            .frame(width: 2.5)
            .scaleEffect(y: animating ? (phase ? high : low) : 0.25, anchor: .center)
            .animation(
                animating ? .easeInOut(duration: speed).repeatForever(autoreverses: true) : .easeOut(duration: 0.2),
                value: phase
            )
            .animation(.easeOut(duration: 0.2), value: animating)
    }
}
