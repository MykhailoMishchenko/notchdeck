import Foundation
import NotchDeckShared
import ServiceManagement

// inputs {}, does {XPC client for the privileged fan helper + SMAppService registration plumbing}, returns {singleton}
final class FanControlClient {
    static let shared = FanControlClient()
    static let daemonPlistName = "dev.notchdeck.fanhelperd.plist"

    private var connection: NSXPCConnection?

    var daemonStatus: SMAppService.Status {
        SMAppService.daemon(plistName: Self.daemonPlistName).status
    }

    // inputs {}, does {registers the embedded daemon (user then approves in System Settings)}, returns {error text or nil}
    func registerDaemon() -> String? {
        do {
            try SMAppService.daemon(plistName: Self.daemonPlistName).register()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // inputs {}, does {unregisters the daemon}, returns {error text or nil}
    func unregisterDaemon() -> String? {
        setMode(manual: false) { _ in }
        do {
            try SMAppService.daemon(plistName: Self.daemonPlistName).unregister()
            invalidate()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func setMode(manual: Bool, reply: @escaping (Bool) -> Void) {
        proxy(reply: reply)?.setMode(manual, reply: reply)
    }

    func setTarget(fan: Int, rpm: Double, reply: @escaping (Bool) -> Void) {
        proxy(reply: reply)?.setTarget(fan: fan, rpm: rpm, reply: reply)
    }

    func status(reply: @escaping (Bool, String) -> Void) {
        guard let proxy = proxy(reply: { ok in reply(ok, "") }) else { return }
        proxy.status(reply: reply)
    }

    // inputs {failure reply}, does {lazily opens the privileged mach connection; failures answer the caller with false}, returns {proxy or nil}
    private func proxy(reply: @escaping (Bool) -> Void) -> FanControlXPCProtocol? {
        if connection == nil {
            let new = NSXPCConnection(machServiceName: fanHelperMachServiceName, options: .privileged)
            new.remoteObjectInterface = NSXPCInterface(with: FanControlXPCProtocol.self)
            new.invalidationHandler = { [weak self] in self?.connection = nil }
            new.resume()
            connection = new
        }
        let remote = connection?.remoteObjectProxyWithErrorHandler { [weak self] error in
            Log.info("fan xpc error: \(error.localizedDescription)")
            self?.invalidate()
            reply(false)
        }
        return remote as? FanControlXPCProtocol
    }

    private func invalidate() {
        connection?.invalidate()
        connection = nil
    }
}
