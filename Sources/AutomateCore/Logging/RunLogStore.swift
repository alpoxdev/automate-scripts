import Foundation

public final class RunLogStore: @unchecked Sendable {
    public let directory: URL
    public var stashDirectory: URL { directory.appendingPathComponent("Stash", isDirectory: true) }
    public var stashedFilesDirectory: URL { stashDirectory.appendingPathComponent("Files", isDirectory: true) }
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL = RunLogStore.defaultDirectory()) {
        self.directory = directory
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AutomateScripts/RunLogs", isDirectory: true)
    }

    public func prepareOutputURLs(for job: ScriptJob, runID: UUID = UUID()) throws -> (runID: UUID, stdout: URL, stderr: URL) {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let runDirectory = directory.appendingPathComponent(logFolderName(for: job), isDirectory: true)
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        let prefix = runID.uuidString
        return (runID, runDirectory.appendingPathComponent("\(prefix).stdout.log"), runDirectory.appendingPathComponent("\(prefix).stderr.log"))
    }

    public func append(_ record: RunRecord) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = recordsURL(for: record.jobID)
        var records = try records(for: record.jobID)
        records.insert(record, at: 0)
        records = Array(records.prefix(100))
        try encoder.encode(records).write(to: url, options: [.atomic])
    }

    public func records(for jobID: UUID) throws -> [RunRecord] {
        let url = recordsURL(for: jobID)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try decoder.decode([RunRecord].self, from: Data(contentsOf: url))
    }

    public func stashedRecords(for jobID: UUID) throws -> [RunRecord] {
        let url = stashedRecordsURL(for: jobID)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try decoder.decode([RunRecord].self, from: Data(contentsOf: url))
    }

    @discardableResult
    public func stashLogs(olderThanDays days: Int, now: Date = Date()) throws -> LogStashSummary {
        let cutoff = now.addingTimeInterval(-TimeInterval(max(days, 0)) * 24 * 60 * 60)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stashDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stashedFilesDirectory, withIntermediateDirectories: true)

        var summary = LogStashSummary(cutoff: cutoff)
        let recordFiles = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(".runs.json") }

        for recordFile in recordFiles {
            let activeRecords = try decoder.decode([RunRecord].self, from: Data(contentsOf: recordFile))
            let oldRecords = activeRecords.filter { $0.finishedAt < cutoff }
            let recentRecords = activeRecords.filter { $0.finishedAt >= cutoff }
            guard !oldRecords.isEmpty else { continue }

            let jobID = recordFile.lastPathComponent.replacingOccurrences(of: ".runs.json", with: "")
            let stashedURL = stashDirectory.appendingPathComponent("\(jobID).stashed-runs.json")
            var stashedRecords = try loadRecordsIfPresent(stashedURL)
            let movedRecords = try oldRecords.map { try stash(record: $0) }
            stashedRecords.insert(contentsOf: movedRecords, at: 0)
            try encoder.encode(stashedRecords).write(to: stashedURL, options: [.atomic])
            try encoder.encode(recentRecords).write(to: recordFile, options: [.atomic])
            summary.stashedRuns += movedRecords.count
            summary.remainingRuns += recentRecords.count
        }

        return summary
    }

    private func recordsURL(for jobID: UUID) -> URL { directory.appendingPathComponent("\(jobID.uuidString).runs.json") }
    private func stashedRecordsURL(for jobID: UUID) -> URL { stashDirectory.appendingPathComponent("\(jobID.uuidString).stashed-runs.json") }

    private func logFolderName(for job: ScriptJob) -> String {
        let safeName = job.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .map { character -> Character in
                character.isLetter || character.isNumber || character == "-" || character == "_" ? character : "-"
            }
            .reduce("") { $0 + String($1) }
        let name = safeName.isEmpty ? "job" : safeName
        return "\(name)-\(job.id.uuidString)"
    }

    private func loadRecordsIfPresent(_ url: URL) throws -> [RunRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try decoder.decode([RunRecord].self, from: Data(contentsOf: url))
    }

    private func stash(record: RunRecord) throws -> RunRecord {
        var updated = record
        updated.stdoutPath = try moveLogFileIfPresent(record.stdoutPath)
        updated.stderrPath = try moveLogFileIfPresent(record.stderrPath)
        return updated
    }

    private func moveLogFileIfPresent(_ path: String?) throws -> String? {
        guard let path, FileManager.default.fileExists(atPath: path) else { return path }
        let source = URL(fileURLWithPath: path)
        let destination = uniqueDestination(for: source.lastPathComponent)
        try FileManager.default.createDirectory(at: stashedFilesDirectory, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: source, to: destination)
        return destination.path
    }

    private func uniqueDestination(for fileName: String) -> URL {
        var candidate = stashedFilesDirectory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }
        let base = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        var index = 1
        repeat {
            let name = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
            candidate = stashedFilesDirectory.appendingPathComponent(name)
            index += 1
        } while FileManager.default.fileExists(atPath: candidate.path)
        return candidate
    }
}

public struct LogStashSummary: Equatable, Sendable {
    public var cutoff: Date
    public var stashedRuns: Int = 0
    public var remainingRuns: Int = 0
}
