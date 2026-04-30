import Foundation

public enum CommandSafety: Sendable {
    public static func warnings(command: String, arguments: [String]) -> [String] {
        let tokens = ([command] + arguments).map { $0.lowercased() }
        let joined = tokens.joined(separator: " ")
        var warnings: [String] = []
        if joined.contains("rm -rf /") || joined.contains("rm -fr /") { warnings.append("Refusing obviously destructive root removal command.") }
        if tokens.contains("shutdown") || tokens.contains("reboot") { warnings.append("Command may restart or power off the system.") }
        if joined.contains("sudo ") || command == "sudo" { warnings.append("Command requires elevated privileges and may not work from a background scheduler.") }
        return warnings
    }

    public static func isBlocked(command: String, arguments: [String]) -> Bool {
        warnings(command: command, arguments: arguments).contains { $0.contains("Refusing") }
    }
}
