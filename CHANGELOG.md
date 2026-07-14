# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows [SemVer](https://semver.org/).
Every feature release: bump `VERSION`, add an entry here, tag `vX.Y.Z`.

## [0.3.0] — 2026-07-14

### Added
- **Media widget** (push-based): current track, artist and play/pause/skip for Spotify and Apple Music. State arrives via `DistributedNotificationCenter` broadcasts (true push); controls go through AppleScript. Note: `MPNowPlayingInfoCenter` only reflects the app's own playback and Apple restricted the private MediaRemote API in macOS 15.4+, so the notification + AppleScript pair is the honest public-API route.
- **Files shelf widget**: drag files onto the card — they are copied into temp storage and listed with icons; AirDrop the whole shelf via `NSSharingService`; clear removes the temp copies.
- **Calendar widget** (poll-based, 30 s): clock, date and the next non-all-day event within 24 h via EventKit, with graceful no-access state.
- Usage descriptions (calendar, Apple Events) in the app bundle plist and embedded into the bare dev binary (`__info_plist` section) so TCC prompts work under `swift run` too.

### Changed
- Panel header (app title + quit button) removed — the panel is pure widget space now. Quit via `pkill NotchDeck` until Settings (0.4.0).
- Widget architecture claim verified: all three widgets touch the core in exactly one line each (registration in `AppDelegate.registerWidgets`).

### Fixed
- App-wide UI freeze on first expand: the media widget ran AppleScript synchronously on the main thread, and the TCC permission prompt blocked rendering. All Apple Events now run off the main thread.

## [0.2.0] — 2026-07-14

### Added
- Widget platform core: the `NotchWidget` protocol (id, views, `updateInterval`, `holdsExpanded` live-lock, `refresh`, visibility lifecycle) with protocol-extension defaults — a minimal widget is ~15 lines.
- `WidgetRegistry`: single registration point, duplicate-id protection, display order persisted to `UserDefaults`.
- Drag & drop widget reorder inside the expanded panel, with live reordering while dragging.
- Push and poll update models: push widgets publish their own updates; poll widgets get `refresh()` on their interval plus once on appear, timers active only while the panel is visible.
- Live-lock: a widget reporting `holdsExpanded == true` keeps the panel open; collapse retries every second until released.
- Visibility lifecycle across multiple screens: `onAppear` on first visible panel, `onDisappear` when none remain.
- Three placeholder widgets (Music / Files / Calendar) proving the pipeline; replaced by real ones in 0.3.0.

## [0.1.0] — 2026-07-14

### Added
- Notch window core: borderless `NSPanel` at `.statusBar` level, present on all Spaces and above fullscreen apps.
- Hover expand/collapse with spring animation (0.38 open / 0.30 close, 100 ms collapse grace delay).
- Hover trigger zone larger than the visible shape (+14 pt sides, +8 pt below) — expansion starts as the cursor approaches.
- Runtime notch geometry detection (`safeAreaInsets` + auxiliary areas) with a per-model calibration table; the MacBook Pro 16" M1 Pro 2021 entry verified on real hardware (185×32 pt at 1728×1117).
- Pill fallback for displays without a notch (external monitors), sharing the same code path.
- Multi-monitor: one window per display, hot plug/unplug handling.
- Click-through: mouse events pass through the invisible part of the window (menu bar stays usable).
- Expanded panel content fades in after the shape opens (150 ms) and disappears instantly (80 ms) on collapse.
- `scripts/bundle.sh` — builds `NotchDeck.app` (`LSUIElement`, ad-hoc signed) with the version injected from `VERSION`.
