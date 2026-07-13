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

## Stage 2 — NotchWidget protocol (DRAFT, to be finalized in Stage 2)

```swift
protocol NotchWidget {
    var id: String { get }
    var displayName: String { get }
    var collapsedView: AnyView { get }
    var expandedView: AnyView { get }
    var updateInterval: TimeInterval? { get }   // nil = push-based
    func onAppear()
    func onDisappear()
}
```

Planned decisions (to be refined during implementation):
- **WidgetRegistry** — the single registration point; display order is persisted, drag & drop reorder.
- **Push vs poll**: `updateInterval == nil` ⇒ the widget publishes its own updates (ObservableObject/Combine); otherwise the platform polls it on a timer, only while the widget is visible.
- **Live-lock**: a `holdsExpanded` mechanism — a widget tells the platform "live update in progress, don't collapse" (the temperature-sensor case).
- **External-process-backed widgets** (Stage 4): a wrapper widget whose data source is XPC/socket to an external privileged daemon. The platform itself requires no elevated privileges; entitlements stay minimal. Fan control will plug in as a regular `NotchWidget` that talks XPC internally.

## Build

- SPM executable (no Xcode project); `swift run NotchDeck` for development.
- `scripts/bundle.sh [debug|release]` — builds `NotchDeck.app` (`LSUIElement=true`, ad-hoc signed, version injected from the `VERSION` file). The bundle is required for `SMAppService` (launch at login, Stage 3.5).
