import Foundation

public let helperMachServiceName = "local.FermataNeo.Helper"

/// Bump when the helper's behaviour or protocol changes, so the app offers a reinstall.
public let helperVersion = 1

@objc public protocol HelperProtocol {
    /// Turns the system-wide "SleepDisabled" power setting on or off for this connection.
    /// Replies with the IOReturn code (0 on success).
    func setSleepDisabled(_ disabled: Bool, reply: @escaping (Int32) -> Void)

    func getVersion(reply: @escaping (Int) -> Void)
}
