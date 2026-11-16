import Foundation

/// Installs or removes the root helper by running a bundled shell script with an
/// administrator password prompt.
enum HelperInstaller {
    static func install() -> String? {
        guard let script = Bundle.main.path(forResource: "install-helper", ofType: "sh"),
              let plist = Bundle.main.path(forResource: "local.FermataNeo.Helper", ofType: "plist"),
              let binary = Bundle.main.path(forAuxiliaryExecutable: "FermataNeoHelper")
        else { return "The helper files are missing from the app bundle." }
        return runAsAdmin([script, binary, plist])
    }

    static func uninstall() -> String? {
        guard let script = Bundle.main.path(forResource: "uninstall-helper", ofType: "sh")
        else { return "The uninstall script is missing from the app bundle." }
        return runAsAdmin([script])
    }

    /// Returns nil on success, or an error message. Returns "" if the user cancelled.
    private static func runAsAdmin(_ arguments: [String]) -> String? {
        let parts = (["/bin/sh"] + arguments).map { "quoted form of \(appleScriptLiteral($0))" }
        let source = "do shell script " + parts.joined(separator: " & \" \" & ")
            + " with administrator privileges"

        var errorInfo: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
        guard let errorInfo else { return nil }

        if (errorInfo[NSAppleScript.errorNumber] as? Int) == -128 { return "" }
        return (errorInfo[NSAppleScript.errorMessage] as? String) ?? "Unknown error"
    }

    private static func appleScriptLiteral(_ string: String) -> String {
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
