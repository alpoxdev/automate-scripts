import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var logRetentionDays: Int
    public var runsInBackground: Bool

    public init(logRetentionDays: Int = 14, runsInBackground: Bool = true) {
        self.logRetentionDays = logRetentionDays
        self.runsInBackground = runsInBackground
    }
}

public final class AppSettingsStore: @unchecked Sendable {
    public let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL = AppSettingsStore.defaultFileURL()) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public static func defaultFileURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AutomateScripts", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    public func load() throws -> AppSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return AppSettings() }
        return try decoder.decode(AppSettings.self, from: Data(contentsOf: fileURL))
    }

    public func save(_ settings: AppSettings) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(settings).write(to: fileURL, options: [.atomic])
    }
}
