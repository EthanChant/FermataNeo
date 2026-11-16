import Foundation
import FermataNeoShared

enum HelperError: Error {
    /// The helper could not be reached (not installed, or the connection failed).
    case unavailable(String)
    /// The helper ran but the system refused the change.
    case rejected(Int32)

    var message: String {
        switch self {
        case .unavailable(let detail): return "helper not reachable (\(detail))"
        case .rejected(let code): return String(format: "the system refused the change (0x%x)", code)
        }
    }
}

/// Talks to the root helper. The connection is kept open on purpose: the helper restores
/// normal sleep as soon as it closes. All callbacks arrive on the main queue.
final class HelperClient {
    /// The helper process restarted; any sleep prevention it held is gone.
    var onInterrupted: (() -> Void)?
    /// The connection is dead (for example the helper was uninstalled).
    var onInvalidated: (() -> Void)?

    private var connection: NSXPCConnection?

    private func activeConnection() -> NSXPCConnection {
        if let connection { return connection }

        // Test hooks: point at a helper registered as a per-user launch agent.
        let env = ProcessInfo.processInfo.environment
        let name = env["FERMATANEO_HELPER_SERVICE"] ?? helperMachServiceName
        let options: NSXPCConnection.Options = env["FERMATANEO_HELPER_USER_DOMAIN"] != nil ? [] : .privileged

        let new = NSXPCConnection(machServiceName: name, options: options)
        new.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        new.interruptionHandler = { [weak self] in
            DispatchQueue.main.async { self?.onInterrupted?() }
        }
        new.invalidationHandler = { [weak self, weak new] in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.connection === new { self.connection = nil }
                self.onInvalidated?()
            }
        }
        new.resume()
        connection = new
        return new
    }

    private func proxy(onError: @escaping (HelperError) -> Void) -> HelperProtocol? {
        let object = activeConnection().remoteObjectProxyWithErrorHandler { error in
            DispatchQueue.main.async { onError(.unavailable(error.localizedDescription)) }
        }
        return object as? HelperProtocol
    }

    func setSleepDisabled(_ disabled: Bool, completion: @escaping (HelperError?) -> Void) {
        guard let proxy = proxy(onError: { completion($0) }) else {
            completion(.unavailable("bad proxy"))
            return
        }
        proxy.setSleepDisabled(disabled) { status in
            DispatchQueue.main.async { completion(status == 0 ? nil : .rejected(status)) }
        }
    }

    /// Calls back with the installed helper's version, or nil if it cannot be reached.
    func getVersion(completion: @escaping (Int?) -> Void) {
        guard let proxy = proxy(onError: { _ in completion(nil) }) else {
            completion(nil)
            return
        }
        proxy.getVersion { version in
            DispatchQueue.main.async { completion(version) }
        }
    }

    func disconnect() {
        connection?.invalidationHandler = nil
        connection?.invalidate()
        connection = nil
    }
}
