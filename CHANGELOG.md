# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows [SemVer](https://semver.org/).
Every feature release: bump `VERSION`, add an entry here, tag `vX.Y.Z`.

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
