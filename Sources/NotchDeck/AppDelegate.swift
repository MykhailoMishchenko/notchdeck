import AppKit

// inputs {}, does {maintains one NotchWindowController per connected screen, rebuilds on display config changes}, returns {app delegate}
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controllers: [CGDirectDisplayID: NotchWindowController] = [:]
    private let registry = WidgetRegistry()

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerWidgets()
        rebuildControllers()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screensChanged() {
        rebuildControllers()
    }

    // inputs {}, does {registers the widget set (placeholders until 0.3.0 real widgets land)}, returns {}
    private func registerWidgets() {
        registry.register(PlaceholderWidget(id: "demo.music", displayName: "Music", icon: "music.note"))
        registry.register(PlaceholderWidget(id: "demo.files", displayName: "Files", icon: "tray.full"))
        registry.register(PlaceholderWidget(id: "demo.calendar", displayName: "Calendar", icon: "calendar"))
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
