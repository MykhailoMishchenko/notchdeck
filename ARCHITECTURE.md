# NotchDeck — Architecture

A modular notch platform for macOS. This file is the source of truth for architectural decisions; consult it when integrating external modules (fan control and others).

## Layers

```
┌─────────────────────────────────────────────┐
│  App (main.swift, AppDelegate)              │  lifecycle, per-screen windows
├─────────────────────────────────────────────┤
│  Notch Layer (NotchWindow, Controller,      │  window, geometry, hover,
│  NotchGeometry)                             │  expand/collapse, pill fallback
├─────────────────────────────────────────────┤
│  Widget Platform (Stage 2)                  │  NotchWidget protocol, registry,
│                                             │  push/poll scheduling, live-lock
├─────────────────────────────────────────────┤
│  Widgets (Stage 3)                          │  media / files shelf / calendar,
│                                             │  later: fan control (XPC)
└─────────────────────────────────────────────┘
```

Dependency rule: each layer knows only about the layer below. Widgets know nothing about the window; the core knows nothing about concrete widgets.

## Stage 1 — window decisions (implemented)

### Geometry
- **Primary source — runtime**: `NSScreen.safeAreaInsets.top > 0` ⇒ the screen has a notch; cutout width = `frame.width − auxiliaryTopLeftArea.width − auxiliaryTopRightArea.width`.
- **Calibration table** `NotchGeometry.calibrated: [ModelIdentifier: NotchGeometry]` — corner radii and fallback values. The MVP ships a single entry: `MacBookPro18,1/18,2` (16" M1 Pro/Max 2021), verified on real hardware (185×32 pt at the default 1728×1117 logical resolution — point values scale with the resolution setting, which is exactly why runtime detection stays primary). New models are one line each.
- Screen without a notch ⇒ `NotchGeometry.pill` — the same view renders as a pill at the top edge. One code path; only the shape differs.

### Window
- `NSPanel` (`.borderless`, `.nonactivatingPanel`): never steals focus from the active app on hover or click.
- `level = .statusBar` — above the menu bar; `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]` — lives on all Spaces and above fullscreen apps.
- **The window always has the expanded size** — the shape animates inside SwiftUI (spring, open 0.38 / close 0.30, damping 0.78), not the window frame. Live `NSWindow` resizing stutters; every mature notch app does the same.
- Consequence: the invisible part of the window overlaps the menu bar ⇒ `PassThroughHostingView.hitTest` passes mouse events through everywhere outside the current interactive zone (the cutout when collapsed / the panel when expanded). The zone is provided by the controller, not by SwiftUI — a single source of truth.
- Hover events are noisy while SwiftUI rebuilds tracking areas during the shape animation, so the delayed collapse re-checks the REAL cursor position (`NSEvent.mouseLocation`) against the interactive zone and aborts if the cursor is still inside.
- The hoverable view is larger than the visible shape (transparent margin + `contentShape`): the trigger zone and the hit-test zone are derived from the same formula.

### Multi-monitor
- `AppDelegate` keeps `[CGDirectDisplayID: NotchWindowController]` and diffs it on `NSApplication.didChangeScreenParametersNotification`: screen connected — controller created (notch or pill decided by `NotchGeometry.detect`), disconnected — torn down, frame changed — recreated.

## Stage 2 — widget platform (implemented)

### The `NotchWidget` protocol

```swift
protocol NotchWidget: AnyObject {
    var id: String { get }                      // stable unique id (order persistence, settings)
    var displayName: String { get }
    var collapsedView: AnyView { get }          // default: EmptyView
    var expandedView: AnyView { get }           // card inside the expanded panel
    var updateInterval: TimeInterval? { get }   // nil = push-based; default nil
    var holdsExpanded: Bool { get }             // live-lock; default false
    func refresh()                              // poll target; default no-op
    func onAppear()                             // panel visible on >=1 screen; default no-op
    func onDisappear()                          // panel visible nowhere; default no-op
}
```

Everything except `id`, `displayName`, `expandedView` has a default via a protocol extension — a minimal widget is ~15 lines. Adding a widget = implement the protocol + one `registry.register(...)` line; the core does not change (proven by the three Stage 3 widgets).

### WidgetRegistry
- The single registration point; duplicate ids are rejected.
- **Order**: persisted to `UserDefaults` (`dev.notchdeck.widgetOrder`); drag & drop reorder in the panel (`onDrag`/`DropDelegate`, live reordering on `dropEntered`). The persisted-order sort is stability-corrected (Swift's sort is not stable).
- **Push vs poll**: `updateInterval == nil` ⇒ the widget publishes its own updates (it is an `ObservableObject` internally and its views observe it directly — the platform is not involved). Otherwise the registry runs a timer per widget and calls `refresh()`, plus one `refresh()` immediately on appear. Timers run only while the panel is visible somewhere.
- **Visibility lifecycle**: the registry counts visible panels across screens; `onAppear`/polling start when the first panel expands, `onDisappear`/timer teardown when the last one collapses. One registry serves all screens.
- **Live-lock**: `holdsExpanded` is *pulled* at collapse-decision time. If any visible widget holds, the collapse attempt re-schedules itself every 1 s until released (or until the cursor returns). Pull keeps the protocol passive — no callback plumbing into widgets. This is the temperature-sensor case: the panel stays open while a live reading is being rendered.

### Panel UI
- `WidgetPanelView` is the only view that knows about the registry; `WidgetCardView` provides uniform card chrome around each widget's `expandedView`.

## Stage 3 — MVP widgets (implemented)

Three widgets, each exercising a different integration type. Each touches the core in exactly one line (`registry.register(...)` in `AppDelegate`) — the extensibility claim holds.

| Widget | Type | Integration |
|---|---|---|
| `MediaWidget` | push | `DistributedNotificationCenter` (`com.spotify.client.PlaybackStateChanged`, `com.apple.Music.playerInfo`) for state; AppleScript for play/pause/skip; one AppleScript pull on appear for initial state |
| `FilesShelfWidget` | filesystem / share | `onDrop` of `fileURL` → copy into temp shelf dir; `NSSharingService(.sendViaAirDrop)`; clear deletes temp copies |
| `CalendarWidget` | poll (30 s) | EventKit next-event within 24 h + clock; graceful denied state |

Decisions & lessons:
- **Why not `MPNowPlayingInfoCenter`**: it only reflects the app's *own* playback; the system-wide MediaRemote API is private and Apple gated it behind an entitlement in macOS 15.4+. Player-broadcast notifications + AppleScript are the honest public route (covers Spotify and Apple Music).
- **Apple Events never run on the main thread**: a synchronous `NSAppleScript` triggered a TCC prompt that froze the entire UI before first render. All script calls go through a background queue; results publish back on main.
- **TCC in dev runs**: the bare SPM binary embeds an Info.plist (`-sectcreate __TEXT __info_plist`) with usage descriptions so calendar/Apple Events prompts work without the .app bundle; `bundle.sh` carries the same keys.
- `PlaceholderWidget` is kept as the minimal reference implementation of the protocol.

## Build

- SPM executable (no Xcode project); `swift run NotchDeck` for development.
- `scripts/bundle.sh [debug|release]` — builds `NotchDeck.app` (`LSUIElement=true`, ad-hoc signed, version injected from the `VERSION` file). The bundle is required for `SMAppService` (launch at login, Stage 3.5).
