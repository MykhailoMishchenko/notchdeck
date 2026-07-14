import Foundation
import NotchDeckShared
import os

// Root launchd daemon (SMAppService.daemon). Owns SMC WRITES; the app stays unprivileged.
// Safety model:
//  - only F#Md / F#Tg keys are ever written, target clamped to the fan's [min, max];
//  - when the last client connection drops while manual mode is engaged, fans revert to AUTO
//    (an app crash can never leave the machine with pinned fans).

let helperVersion = "1.0.0"
let logger = Logger(subsystem: "dev.notchdeck.fanhelperd", category: "helper")

// inputs {}, does {implements the XPC contract with clamped SMC writes and auto-revert bookkeeping}, returns {service}
final class FanControlService: NSObject, FanControlXPCProtocol {
    private(set) var manualEngaged = false

    func setMode(_ manual: Bool, reply: @escaping (Bool) -> Void) {
        var ok = true
        for fan in 0..<SMC.fanCount {
            ok = SMC.writeValue("F\(fan)Md", manual ? 1 : 0) && ok
        }
        manualEngaged = manual
        logger.notice("setMode manual=\(manual) ok=\(ok)")
        reply(ok)
    }

    func setTarget(fan: Int, rpm: Double, reply: @escaping (Bool) -> Void) {
        guard fan >= 0, fan < SMC.fanCount else {
            reply(false)
            return
        }
        let minRPM = SMC.readValue("F\(fan)Mn") ?? 0
        let maxRPM = SMC.readValue("F\(fan)Mx") ?? 6000
        let clamped = max(minRPM, min(maxRPM, rpm))
        var ok = SMC.writeValue("F\(fan)Md", 1)
        ok = SMC.writeValue("F\(fan)Tg", clamped) && ok
        manualEngaged = true
        logger.notice("setTarget fan=\(fan) rpm=\(clamped) ok=\(ok)")
        reply(ok)
    }

    func status(reply: @escaping (Bool, String) -> Void) {
        reply(true, helperVersion)
    }

    // inputs {}, does {safety net: a client vanished — hand the fans back to the SMC}, returns {}
    func revertToAutoIfEngaged() {
        guard manualEngaged else { return }
        for fan in 0..<SMC.fanCount {
            SMC.writeValue("F\(fan)Md", 0)
        }
        manualEngaged = false
        logger.notice("client dropped — fans reverted to auto")
    }
}

// inputs {}, does {accepts XPC connections, wires the shared service, reverts to auto when the last connection dies}, returns {delegate}
final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service = FanControlService()
    private var connections = 0

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: FanControlXPCProtocol.self)
        connection.exportedObject = service
        connections += 1
        let onDrop: () -> Void = { [weak self] in
            guard let self else { return }
            self.connections -= 1
            if self.connections <= 0 {
                self.service.revertToAutoIfEngaged()
            }
        }
        connection.invalidationHandler = onDrop
        connection.resume()
        logger.notice("client connected (\(self.connections))")
        return true
    }
}

let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: fanHelperMachServiceName)
listener.delegate = delegate
listener.resume()
logger.notice("fan helper \(helperVersion) up")
RunLoop.main.run()
