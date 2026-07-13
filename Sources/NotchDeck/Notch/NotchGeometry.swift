import AppKit

// inputs {}, does {describes the physical notch cutout and derived UI metrics for one screen}, returns {value type}
struct NotchGeometry: Equatable {
    /// Width of the physical camera housing cutout, in points.
    var notchWidth: CGFloat
    /// Height of the cutout (equals menu bar height on notched screens), in points.
    var notchHeight: CGFloat
    /// Radius of the top corners where the cutout meets the screen edge (curves outward).
    var topCornerRadius: CGFloat
    /// Radius of the bottom corners of the cutout (curves inward).
    var bottomCornerRadius: CGFloat

    /// Calibrated values per hardware model. MVP ships ONLY the 16" M1 Pro 2021 entry
    /// (MacBookPro18,1 / 18,2 — M1 Pro / M1 Max share the same panel).
    /// Add new models here later; runtime detection below remains the primary source.
    static let calibrated: [String: NotchGeometry] = [
        "MacBookPro18,1": .macBookPro16_2021,
        "MacBookPro18,2": .macBookPro16_2021,
    ]

    /// MacBook Pro 16" 2021: verified on real hardware (MacBookPro18,1, macOS 26.5).
    /// At the default 1728×1117 logical resolution: safeAreaInsets.top = 32.0,
    /// auxiliary areas leave a 185 pt wide cutout. Point values scale with the
    /// user's resolution setting — which is why runtime detection stays primary.
    static let macBookPro16_2021 = NotchGeometry(
        notchWidth: 185,
        notchHeight: 32,
        topCornerRadius: 6,
        bottomCornerRadius: 10
    )

    /// Fallback pill metrics for screens without a notch (external monitors).
    static let pill = NotchGeometry(
        notchWidth: 190,
        notchHeight: 30,
        topCornerRadius: 6,
        bottomCornerRadius: 14
    )

    // inputs {screen}, does {detects notch geometry: runtime NSScreen data first, calibrated model dict as fallback}, returns {geometry or nil when screen has no notch}
    static func detect(for screen: NSScreen) -> NotchGeometry? {
        guard screen.safeAreaInsets.top > 0 else { return nil }

        let calibratedEntry = calibrated[Self.modelIdentifier() ?? ""]

        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let runtimeWidth = screen.frame.width - left.width - right.width
            if runtimeWidth > 0 {
                return NotchGeometry(
                    notchWidth: runtimeWidth,
                    notchHeight: screen.safeAreaInsets.top,
                    topCornerRadius: calibratedEntry?.topCornerRadius ?? 6,
                    bottomCornerRadius: calibratedEntry?.bottomCornerRadius ?? 10
                )
            }
        }
        return calibratedEntry
    }

    // inputs {}, does {reads hw.model via sysctl}, returns {e.g. "MacBookPro18,1" or nil}
    static func modelIdentifier() -> String? {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }
}
