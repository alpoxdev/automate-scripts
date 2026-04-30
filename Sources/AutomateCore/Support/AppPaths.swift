import Foundation

public enum AppPaths: Sendable {
    public static func applicationSupportDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AutomateScripts", isDirectory: true)
    }

    public static func defaultWorkingDirectory() -> URL {
        applicationSupportDirectory().appendingPathComponent("Workspace", isDirectory: true)
    }

    public static func ensureDefaultWorkingDirectory() throws -> URL {
        let url = defaultWorkingDirectory()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
