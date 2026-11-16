import Foundation
import FermataNeoShared
import PowerSPI

// Root launch daemon. Its only job is flipping the "SleepDisabled" power setting.
//
// Dead-man switch: sleep stays disabled only while the client that asked for it keeps
// its XPC connection open. If that client quits, crashes or is killed, normal sleep is
// restored. It is also restored when the helper starts (boot) and when it is stopped.

final class Helper: NSObject, NSXPCListenerDelegate {
    private let lock = NSLock()
    private var holders = Set<UUID>()
    /// Test hook: log instead of changing the real setting.
    private let dryRun = ProcessInfo.processInfo.environment["FERMATANEO_DRY_RUN"] != nil

    @discardableResult
    private func apply(_ disabled: Bool) -> Int32 {
        if dryRun {
            NSLog("[dry run] SleepDisabled -> %d", disabled ? 1 : 0)
            return 0
        }
        let value: CFBoolean = disabled ? kCFBooleanTrue : kCFBooleanFalse
        let status = IOPMSetSystemPowerSetting("SleepDisabled" as CFString, value)
        NSLog("SleepDisabled -> %d (status 0x%x)", disabled ? 1 : 0, status)
        return status
    }

    func reset() {
        lock.lock()
        holders.removeAll()
        apply(false)
        lock.unlock()
    }

    func set(_ token: UUID, disabled: Bool) -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        if disabled {
            holders.insert(token)
        } else {
            holders.remove(token)
        }
        let status = apply(!holders.isEmpty)
        if status != 0 && disabled {
            holders.remove(token)
        }
        return status
    }

    func connectionClosed(_ token: UUID) {
        lock.lock()
        defer { lock.unlock() }
        if holders.remove(token) != nil && holders.isEmpty {
            NSLog("Client went away while holding sleep prevention; restoring sleep")
            apply(false)
        }
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let session = Session(helper: self)
        let token = session.token
        connection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.exportedObject = session
        connection.invalidationHandler = { [weak self] in self?.connectionClosed(token) }
        connection.interruptionHandler = { [weak self] in self?.connectionClosed(token) }
        connection.resume()
        return true
    }
}

final class Session: NSObject, HelperProtocol {
    let token = UUID()
    private let helper: Helper

    init(helper: Helper) {
        self.helper = helper
    }

    func setSleepDisabled(_ disabled: Bool, reply: @escaping (Int32) -> Void) {
        reply(helper.set(token, disabled: disabled))
    }

    func getVersion(reply: @escaping (Int) -> Void) {
        reply(helperVersion)
    }
}

// An alternate service name can be passed as the first argument (used for testing).
let serviceName = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : helperMachServiceName

let helper = Helper()
helper.reset()

signal(SIGTERM, SIG_IGN)
let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termSource.setEventHandler {
    helper.reset()
    exit(0)
}
termSource.resume()

let listener = NSXPCListener(machServiceName: serviceName)
listener.delegate = helper
listener.resume()

dispatchMain()
