# NotchDeck

**Your MacBook notch, turned into a workspace.** NotchDeck transforms the area around the camera cutout into an interactive panel: hover over it and it smoothly expands into a widget dock; move away and it seamlessly melts back into the notch.

![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-black)
![Swift](https://img.shields.io/badge/Swift-5.10-orange)
![Version](https://img.shields.io/badge/version-0.5.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Hover panel at the notch** — spring-animated expansion on hover, with a trigger zone larger than the visible shape (reacts as the cursor approaches), and snappy collapse when the cursor leaves.
- **Stays out of the system's way** — clicks pass through the invisible part of the window: the menu bar remains fully usable, and the panel never steals focus from the active app.
- **External monitors** — on displays without a notch the panel becomes a compact pill at the top edge. Multi-monitor works out of the box, including hot plug/unplug.
- **Pixel-accurate geometry** — the cutout is detected at runtime via `NSScreen` and the shape is fitted precisely. Calibration verified on a real MacBook Pro 16" M1 Pro 2021.
- **Works everywhere** — across all Spaces and on top of fullscreen apps.

## A modular platform

NotchDeck is not a monolith — it is a platform with a widget system: a new widget is just an implementation of the `NotchWidget` protocol plus one registration line, with zero changes to the core. The MVP roadmap includes three widgets (media controls, a files shelf with AirDrop, calendar) and an extension point for external modules backed by privileged daemons (sensor/fan monitoring over XPC). See [ARCHITECTURE.md](ARCHITECTURE.md) for details.

## Requirements

- macOS 13+
- A MacBook Pro with a notch for notch mode (16" M1 Pro 2021 is the reference; other models via runtime detection), or any Mac for pill mode

## Build & run

```bash
git clone https://github.com/MykhailoMishchenko/notchdeck.git
cd notchdeck
swift run NotchDeck          # dev run
./scripts/bundle.sh release  # build NotchDeck.app
```

## Roadmap

- [x] 0.1.0 — notch window core: hover expand/collapse, pill fallback, multi-monitor
- [x] 0.2.0 — widget system: `NotchWidget` protocol, registry, push/poll updates, reorder
- [x] 0.3.0 — widgets: media controls, files shelf (drag & drop + AirDrop), calendar
- [x] 0.4.0 — Apple Music playlist picker in the media widget
- [x] 0.5.0 — Dynamic Island: album art + equalizer in the collapsed notch, artwork card, swipe-back picker
- [x] 0.6.0 — file drag & drop: strip hint on system drags, Files Tray + AirDrop takeover zones
- [x] 0.7.0 — launcher column, settings (widget toggles), launch at login
- [x] 0.8.0 — Fans widget (SMC monitor, XPC control mount point), Claude usage widget, extension docs
- [x] 0.11.0 — fan CONTROL: embedded privileged XPC helper, per-fan sliders + Auto, crash-safe revert

Versioning: the single source of truth is the [`VERSION`](VERSION) file; releases are tagged `vX.Y.Z`, history lives in [CHANGELOG.md](CHANGELOG.md).

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

The protocol also gives you collapsed Dynamic-Island slots, poll scheduling, a live-lock, full-panel takeovers and a Settings toggle — all for free. Widgets backed by **external processes** are first-class: the Claude widget wraps a CLI, and the fan widget is the designated mount point for a future privileged XPC helper that will add fan *control* on top of today's monitoring. See [ARCHITECTURE.md](ARCHITECTURE.md), Stage 4.

## License

[MIT](LICENSE)
