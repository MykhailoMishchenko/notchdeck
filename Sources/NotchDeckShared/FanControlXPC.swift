import Foundation

/// Mach service name of the privileged fan helper (must match the LaunchDaemons plist).
public let fanHelperMachServiceName = "dev.notchdeck.fanhelperd"

// inputs {}, does {the NARROW XPC contract between the app and the root helper — fan mode/target only, nothing else is exposed}, returns {protocol}
@objc public protocol FanControlXPCProtocol {
    /// manual=false returns ALL fans to SMC automatic control.
    func setMode(_ manual: Bool, reply: @escaping (Bool) -> Void)
    /// Sets the target RPM for one fan; the helper clamps to the fan's [min, max] and forces manual mode.
    func setTarget(fan: Int, rpm: Double, reply: @escaping (Bool) -> Void)
    /// Liveness/version probe.
    func status(reply: @escaping (Bool, String) -> Void)
}
