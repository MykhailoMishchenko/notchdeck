import AppKit

// inputs {}, does {bootstraps NSApplication as accessory app with AppDelegate}, returns {never}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
