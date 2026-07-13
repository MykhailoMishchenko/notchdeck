import AppKit

// inputs {}, does {maintains one NotchWindowController per connected screen, rebuilds on display config changes}, returns {app delegate}
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controllers: [CGDirectDisplayID: NotchWindowController] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
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
                    controllers[id] = NotchWindowController(screen: screen)
                }
            } else {
                controllers[id] = NotchWindowController(screen: screen)
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
