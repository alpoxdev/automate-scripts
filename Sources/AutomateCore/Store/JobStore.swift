import Foundation

public struct JobDatabase: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var jobs: [ScriptJob]

    public init(schemaVersion: Int = 1, jobs: [ScriptJob] = []) {
        self.schemaVersion = schemaVersion
        self.jobs = jobs
    }
}

public final class JobStore: @unchecked Sendable {
    public let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSLock()

    public init(fileURL: URL = JobStore.defaultFileURL()) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("AutomateScripts", isDirectory: true).appendingPathComponent("jobs.json")
    }

    public func load() throws -> JobDatabase {
        lock.lock(); defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return JobDatabase() }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(JobDatabase.self, from: data)
    }

    public func save(_ database: JobDatabase) throws {
        lock.lock(); defer { lock.unlock() }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(database)
        let tmp = fileURL.deletingLastPathComponent().appendingPathComponent(".\(fileURL.lastPathComponent).tmp")
        try data.write(to: tmp, options: [.atomic])
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let backup = fileURL.deletingPathExtension().appendingPathExtension("bak")
            _ = try? FileManager.default.removeItem(at: backup)
            try FileManager.default.copyItem(at: fileURL, to: backup)
            _ = try? FileManager.default.removeItem(at: fileURL)
        }
        try FileManager.default.moveItem(at: tmp, to: fileURL)
    }

    public func list() throws -> [ScriptJob] { try load().jobs.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }

    public func add(_ job: ScriptJob) throws {
        var db = try load()
        guard !db.jobs.contains(where: { $0.name == job.name || $0.id == job.id }) else { throw JobStoreError.duplicateJob(job.name) }
        db.jobs.append(job)
        try save(db)
    }

    public func update(_ job: ScriptJob) throws {
        var db = try load()
        guard let index = db.jobs.firstIndex(where: { $0.id == job.id || $0.name == job.name }) else { throw JobStoreError.jobNotFound(job.name) }
        var updated = job
        updated.updatedAt = Date()
        db.jobs[index] = updated
        try save(db)
    }

    public func find(nameOrID: String) throws -> ScriptJob? {
        let jobs = try load().jobs
        if let id = UUID(uuidString: nameOrID), let byID = jobs.first(where: { $0.id == id }) { return byID }
        return jobs.first { $0.name == nameOrID }
    }

    @discardableResult public func remove(nameOrID: String) throws -> ScriptJob {
        var db = try load()
        guard let index = db.jobs.firstIndex(where: { $0.name == nameOrID || $0.id.uuidString == nameOrID }) else { throw JobStoreError.jobNotFound(nameOrID) }
        let removed = db.jobs.remove(at: index)
        try save(db)
        return removed
    }

    @discardableResult public func setEnabled(nameOrID: String, enabled: Bool) throws -> ScriptJob {
        guard var job = try find(nameOrID: nameOrID) else { throw JobStoreError.jobNotFound(nameOrID) }
        job.enabled = enabled
        try update(job)
        return job
    }
}

public enum JobStoreError: Error, LocalizedError, Equatable, Sendable {
    case duplicateJob(String)
    case jobNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .duplicateJob(let name): "Duplicate job: \(name)"
        case .jobNotFound(let name): "Job not found: \(name)"
        }
    }
}
