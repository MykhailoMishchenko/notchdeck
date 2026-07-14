# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows [SemVer](https://semver.org/).
Every feature release: bump `VERSION`, add an entry here, tag `vX.Y.Z`.

## [0.7.6] — 2026-07-14

### Changed
- The tray is a true buffer now (cut semantics): dropping a file/folder MOVES it into the shelf — it leaves the source folder. The shelf lives in `~/Library/Application Support/NotchDeck/Shelf` and survives restarts (restored on launch).
- Data safety for the only-copy model: the trash button and post-move cleanup send items to the system Trash (recoverable), never hard-delete; the shelf copy of a Finder-moved item is trashed after a 60 s grace so large folder copies can finish.

## [0.7.5] — 2026-07-14

### Changed
- Buffer semantics for drag-out: dropping into **Finder** (a folder or the Desktop) moves the item out of the tray; dropping into **any app** (Telegram, a browser...) shares it and the item stays. The destination is identified by the app owning the window under the drop point (`CGWindowList`, no extra permissions). Dropping INTO the tray still copies — originals are never touched.

## [0.7.4] — 2026-07-14

### Fixed
- Launcher badge clipping for real this time: `LazyVGrid` clips its children — the launcher now uses plain two-per-row stacks.
- Drag-out actually MOVES the item out of the tray: items are dragged via a real AppKit `NSDraggingSource`, and the session-end callback (which SwiftUI's `onDrag` simply doesn't have) removes the item only when the drop was accepted outside the app. The temp copy stays until Clear so the receiver can finish reading.

### Changed
- AirDrop zone is shelved for now (drop routing conflicts); the Files Tray takes the full panel width.
- Every tray item shows its filename under the preview (middle-truncated).

## [0.7.3] — 2026-07-14

### Fixed
- AirDrop zone finally accepts drops: the zone is now a byte-for-byte clone of the tray's working SwiftUI chain — the tap gesture / contentShape / AppKit overlay variants all broke SwiftUI's internal drop routing (NSHostingView owns the drag session and never forwards to AppKit subviews).
- Launcher badge is no longer clipped (smaller, tucked into the corner, zIndex above grid siblings).

### Added
- Drag files OUT of the tray into Finder or any app (`onDrag` per item).
- Tray dedup: the same source file dropped twice stays a single item.

### Changed
- A file drag near the notch now opens the FULL panel (takeover) immediately — the strip stretch is gone in favor of the earlier full expansion.
- AirDrop icon: monochrome SF glyph consistent with the rest of the UI (macOS ships no public "airdrop" symbol — verified).
- The paperplane button is removed from the tray footer.

## [0.7.2] — 2026-07-14

### Fixed
- AirDrop drop target rebuilt on native AppKit (`registerForDraggedTypes`) — SwiftUI's `onDrop` silently never targeted the zone. The icon is the OS-provided one from `NSSharingService`, rendered as-is. "AirDrop all" moved to a paperplane button in the tray footer.

### Changed
- Launcher grid is top-aligned with the neighboring cards.
- Drag proximity stretch triggers earlier (220 pt from the top, ±420 pt from center).

## [0.7.1] — 2026-07-14

### Fixed
- AirDrop zone: the glyph is now a hand-drawn vector (concentric arcs with the bottom wedge cut, like Apple's icon) instead of the fragile `NSSharingService.image` trick; drop modifiers restructured (drop target registered before the tap gesture) with diagnostics.

### Changed
- Launcher squares arranged in a two-column grid (was a single column).
- Drag proximity stretch: when the dragged file gets close to the notch, the strip now also grows 14 pt downward and widens further — reaching toward the cursor before the panel opens.

## [0.7.0] — 2026-07-14

### Added
- **Launcher column** in the center of the panel: small icon squares for every card-less widget (currently the Tray, with a file-count badge) plus a Settings gear. Clicking a square opens that widget's takeover — the tray/AirDrop zones are one click away again.
- **Settings window**: enable/disable each widget (persisted; disabled widgets leave the panel, the launcher, the collapsed slots and stop polling) and **Launch at login** via `SMAppService`. Quit lives here too.

## [0.6.1] — 2026-07-14

### Changed
- The compact Tray card is removed from the panel row — the slot is freed for a future widget (`expandedWidthWeight == 0` now opts a widget out of the row); the tray is reached via file drags.
- Tray contents render as a grid of real previews: QuickLook thumbnails for images/previewable files, native macOS icons for folders and other files; hovering softly zooms only the hovered item (spring, 1.15×).
- AirDrop zone uses Apple's actual AirDrop glyph (from `NSSharingService`), not an SF stand-in.

## [0.6.0] — 2026-07-14

### Added
- **File drag & drop flow** (NotchNook-style): a system-wide file drag makes the collapsed strip widen as a "drop here" hint (global mouse monitor + drag pasteboard, no extra permissions); dragging into the strip expands the panel straight into a two-zone takeover — dashed **Files Tray** (left, drops go to the temp shelf) and blue **AirDrop** (right, drops AirDrop immediately). Clicking the AirDrop zone shares the current shelf.
- **Takeover** as a platform capability: `takeoverView` + `acceptsFileDrops` + `attach(host:)` in the widget protocol; any widget can hold the full panel via the `WidgetHost` handle. Takeover resets when the panel collapses.

### Changed
- The "Drop files here" card is gone: replaced by a compact **Tray** card (icon + file-count badge, 0.7× width) that opens the same two-zone view on click.

## [0.5.12] — 2026-07-14

### Changed
- Space-switch fade removed entirely: WindowServer composites all-Spaces windows only at the end of the swipe, occlusion state lags, and there is no public "space will change" event — every client-side smoothing runs after the system pop and reads as a blink. Native single pop restored (same behavior as NotchNook and the menu bar). Documented in code.

## [0.5.11] — 2026-07-14

### Fixed
- Space-switch fade blinked when the window was already composited: the fade now runs only when the window is genuinely not visible yet (occlusion-state guard).

## [0.5.10] — 2026-07-14

### Changed
- Space switches: the strip fades in (0.35 s ease-out) instead of popping — macOS re-composites all-Spaces windows abruptly at the end of the swipe; we soften it via `activeSpaceDidChangeNotification`.

## [0.5.9] — 2026-07-14

### Fixed
- Playlists are identified by Music's `persistent ID` instead of name: duplicate-named playlists no longer share hover state, and picking one now plays exactly that playlist (name-based play always hit the first match).

## [0.5.8] — 2026-07-14

### Fixed
- Cards painted over each other: the media card's minimum content width (96 pt cover + transport row) exceeded its allocated share and spilled over the neighbor. Media share raised to 1.7×, and every card is now clipped by the platform so no widget can ever overflow onto another.

## [0.5.7] — 2026-07-14

### Changed
- Removed the playlist icon from the top-right corner of the now-playing card; the picker remains reachable from the idle state.

## [0.5.6] — 2026-07-14

### Fixed
- Player text + controls are a compact group vertically centered against the cover (was stretched: title pinned top, controls pinned bottom).

## [0.5.5] — 2026-07-14

### Changed
- Player card matched to the reference precisely: 96 pt cover with larger rounding and badge, bold title, flat transport glyphs (skip-style icons, no circular chrome) under the text.

## [0.5.4] — 2026-07-14

### Fixed
- Empty calendar card ("No events today") is centered again — it inherited the events list's top-leading alignment.

### Changed
- The island hides 60 s after playback is paused and reappears instantly on resume (or on any track change).

## [0.5.3] — 2026-07-14

### Changed
- Player proportions: media card 1.5× (was 2×), cover 70 pt (was 88), tighter fonts, controls and paddings.

## [0.5.2] — 2026-07-14

### Fixed
- Panel collapsed when the cursor was pushed past the top edge of the screen: macOS clamps the cursor to exactly `maxY` there, and `CGRect.contains` excludes the top boundary. The screen-space zone now extends 4 pt above the edge.

## [0.5.1] — 2026-07-14

### Fixed
- Open/close animation broken in 0.5.0: the container refactor swapped differently-sized subtrees instead of morphing one frame — restored the single spring-interpolated frame (now with dynamic island width).
- The island now lights up on app launch when music is already playing (initial state pull at widget init, not only on first expand).

### Changed
- Now-playing card matches the reference layout: large cover art with a source badge (Music red / Spotify green), title / album / artist stack and transport controls to the right.
- Widgets can request wider cards (`expandedWidthWeight`, media = 2×); panel is 520×170.

## [0.5.0] — 2026-07-14

### Added
- **Dynamic Island**: while a track is loaded, the collapsed notch stretches to show the album cover left of the cutout and animated equalizer bars right of it (bars settle when paused). Generic platform feature: widgets got `collapsedLeading`/`collapsedTrailing` slots; the strip self-sizes around active slots with a spring.
- Album artwork in the expanded card: cover art fills the card with transport controls on a gradient scrim and a single playlist icon — no more text-only view. Music artwork comes from the library (`artwork data`), Spotify covers are downloaded from `artwork url`.

### Changed
- Playlist picker redesigned: header removed; back navigation is a right-swipe anywhere on the list (or a single subtle chevron icon); rows highlight on hover.

## [0.4.1] — 2026-07-14

### Fixed
- Panel stayed expanded forever after a three-finger Space switch while hovering: the system gesture swallows the hover-exit event. An expanded-state watchdog now re-checks the real cursor position every 0.5 s and collapses when the cursor left the zone (unless a widget live-lock holds it). Covers Space switches, Mission Control and similar gesture interruptions.

## [0.4.0] — 2026-07-14

### Added
- Apple Music playlist picker in the media widget: when nothing is playing, click the card to browse your library's playlists and start one; the resulting player broadcast flips the card to now-playing automatically. The picker also auto-closes whenever playback starts anywhere (Spotify or Music).

## [0.3.1] — 2026-07-14

### Changed
- Calendar card redesigned: clock/date removed; shows up to 3 upcoming events for the rest of the day, each with its calendar's color bar (as in Calendar.app).

### Fixed
- Calendar TCC flow: prompts only appear for a LaunchServices-launched bundle, and ad-hoc re-signing invalidates the grant on every rebuild — documented; `bundle.sh` now honors `CODESIGN_IDENTITY` for a stable signature.
- Dev logging: unified-log messages upgraded to notice level so they persist for `log show`.

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
