import AppKit

// inputs {}, does {maintains one NotchWindowController per connected screen, rebuilds on display config changes}, returns {app delegate}
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controllers: [CGDirectDisplayID: NotchWindowController] = [:]
    private let registry = WidgetRegistry()

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerWidgets()
        rebuildControllers()
        FileDragMonitor.shared.start()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
    // NOTE: no Space-switch handling on purpose. The system composites all-Spaces windows
    // only at the END of the swipe (single pop, same as NotchNook). There is no public
    // "space WILL change" event, so any client-side fade runs after the pop and reads
    // as a blink. Tried and reverted in 0.5.10–0.5.12.

    @objc private func screensChanged() {
        rebuildControllers()
    }

    // inputs {}, does {registers the MVP widget set — the only place a new widget touches outside its own file}, returns {}
    private func registerWidgets() {
        registry.register(MediaWidget())
        registry.register(FilesShelfWidget())
        registry.register(CalendarWidget())
        registry.register(FanWidget())
        registry.register(ClaudeUsageWidget())
    }

    // inputs {}, does {diffs current screens vs controllers: tears down removed, creates added, rebuilds geometry-changed}, returns {}
    private func rebuildControllers() {
        var seen = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            seen.insert(id)
            if let existing = controllers[id] {
                // Rebuild if the screen's frame changed (resolution/arrangement), else keep as is.
                if existing.screen.frame != screen.frame {
                    existing.tearDown()
                    controllers[id] = NotchWindowController(screen: screen, registry: registry)
                }
            } else {
                controllers[id] = NotchWindowController(screen: screen, registry: registry)
            }
        }
        for (id, controller) in controllers where !seen.contains(id) {
            controller.tearDown()
            controllers.removeValue(forKey: id)
        }
    }
}

extension NSScreen {
    // inputs {}, does {extracts CGDirectDisplayID from deviceDescription}, returns {display id or nil}
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
