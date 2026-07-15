# NotchDeck

**Your MacBook notch, turned into a workspace.** NotchDeck transforms the area around the camera cutout into an interactive panel: hover over it and it smoothly expands into a widget dock; move away and it seamlessly melts back into the notch.

![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-black)
![Swift](https://img.shields.io/badge/Swift-5.10-orange)
![Version](https://img.shields.io/badge/version-0.11.1-blue)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

**Dynamic Island.** While music plays, the collapsed notch stretches to show the album cover and live equalizer bars; a running timer shows an orange progress ring and the remaining time. When the island is idle, Claude's pixel crab occasionally runs out, waves at you and dashes back under the notch.

**Widgets** (hover the notch to expand the panel):
- **Media** — cover art, track / album / artist and transport for Spotify and Apple Music (true push via player broadcasts); when nothing plays, pick any playlist from your Apple Music library right in the notch.
- **Calendar** — today's upcoming events with their real calendar colors (EventKit).
- **Files buffer** — drag any file or folder onto the notch: the strip reaches out toward your drag and opens a tray. Cut semantics: the file *moves* into the buffer (survives app restarts), drag it out into a folder to move it there, or into an app (Telegram, a browser) to share while it stays in the buffer. Deletions go to the system Trash.
- **Fans** — live RPM and CPU/GPU temperatures via user-space SMC reads, plus real **fan speed control** through an embedded privileged helper: per-fan sliders and an Auto button. The helper only ever touches fan keys, clamps to each fan's safe range and hands fans back to the SMC if the app dies.
- **Claude limits** — your actual plan usage, same numbers as Claude Code's `/usage`: session and weekly limits with progress bars and reset times, via your local Claude Code sign-in (the token is never stored or logged).
- **Timer** — presets, start/pause/reset, chime on finish; lives in the island while running.

**Platform.** Widgets are plugins: card row with drag & drop reorder, full-panel takeovers with universal back navigation (chevron or right-swipe), a launcher grid of compact squares, per-widget toggles in Settings, launch at login. Works across Spaces, above fullscreen apps, multi-monitor with a pill fallback on notchless displays.

## Install

1. Download `NotchDeck-<version>.dmg` from [Releases](https://github.com/MykhailoMishchenko/notchdeck/releases), open it and drag **NotchDeck** to **Applications**.
2. The build is not notarized yet, so Gatekeeper will refuse the first launch ("Apple could not verify…"). Clear the quarantine flag:
   ```bash
   xattr -d com.apple.quarantine /Applications/NotchDeck.app
   ```
   or go to System Settings → Privacy & Security and click **Open Anyway** (the old right-click → Open trick no longer works on macOS 15+).
3. Grant what you use: Calendar access (calendar widget), Apple Events (media controls), Keychain read (Claude limits — Connect in Settings), and approve the fan helper in System Settings → Login Items (fan control — Enable in Settings).

## Build from source

```bash
git clone https://github.com/MykhailoMishchenko/notchdeck.git
cd notchdeck
swift run NotchDeck          # dev run (no TCC-gated widgets)
./scripts/bundle.sh release  # build NotchDeck.app
./scripts/dmg.sh             # build the distributable DMG
```

Requirements: macOS 13+, a notched MacBook for notch mode (16" M1 Pro 2021 is the reference; other models via runtime detection) or any Mac for pill mode.

## Extending NotchDeck

A widget is one file + one registration line:

```swift
final class MyWidget: NotchWidget {
    let id = "my"
    let displayName = "My"
    var expandedView: AnyView { AnyView(Text("Hi")) }   // card in the panel row
    // or expandedWidthWeight = 0 + takeoverView -> a launcher square instead
}
// AppDelegate.registerWidgets():
registry.register(MyWidget())
```

The protocol also gives you collapsed Dynamic-Island slots, poll scheduling, a live-lock, full-panel takeovers and a Settings toggle — all for free. Widgets backed by **external processes** are first-class: the Claude widget talks to Anthropic's API with local credentials, and the Fans widget drives a root XPC helper embedded in the same bundle. See [ARCHITECTURE.md](ARCHITECTURE.md).

## Roadmap

Everything from the original MVP spec has shipped (window core → widget platform → media/files/calendar → settings → fan control). On the list:

- [ ] stable code signing + notarization (kills the TCC/Keychain/daemon re-approval pain and the Gatekeeper warning)
- [ ] AirDrop drop zone (parked: NSHostingView drag-routing conflict)
- [ ] more widgets — the platform is open

Versioning: the single source of truth is the [`VERSION`](VERSION) file; releases are tagged `vX.Y.Z`, history lives in [CHANGELOG.md](CHANGELOG.md).

## License

[MIT](LICENSE)
