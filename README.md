# NotchDeck

**Your MacBook notch, turned into a workspace.** NotchDeck transforms the area around the camera cutout into an interactive panel: hover over it and it smoothly expands into a widget dock; move away and it seamlessly melts back into the notch.

![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-black)
![Swift](https://img.shields.io/badge/Swift-5.10-orange)
![Version](https://img.shields.io/badge/version-0.1.0-blue)
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
- [ ] 0.2.0 — widget system: `NotchWidget` protocol, registry, push/poll updates, reorder
- [ ] 0.3.0 — widgets: media controls, files shelf (drag & drop + AirDrop), calendar
- [ ] 0.4.0 — settings: widget toggles, launch at login
- [ ] 0.5.0 — extension point for external-process widgets (XPC) + integration docs

Versioning: the single source of truth is the [`VERSION`](VERSION) file; releases are tagged `vX.Y.Z`, history lives in [CHANGELOG.md](CHANGELOG.md).

## License

[MIT](LICENSE)
