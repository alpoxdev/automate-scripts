import Foundation

public struct ScriptJob: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var description: String?
    public var command: String
    public var arguments: [String]
    public var workingDirectory: String?
    public var requiresAdministratorPrivileges: Bool
    public var environment: [String: String]
    public var schedule: SchedulePreset
    public var enabled: Bool
    public var tags: [String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        command: String,
        arguments: [String] = [],
        workingDirectory: String? = nil,
        requiresAdministratorPrivileges: Bool = false,
        environment: [String: String] = [:],
        schedule: SchedulePreset = .manualOnly,
        enabled: Bool = true,
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.command = command
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.requiresAdministratorPrivileges = requiresAdministratorPrivileges
        self.environment = environment
        self.schedule = schedule
        self.enabled = enabled
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case command
        case arguments
        case workingDirectory
        case requiresAdministratorPrivileges
        case environment
        case schedule
        case enabled
        case tags
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        command = try container.decode(String.self, forKey: .command)
        arguments = try container.decodeIfPresent([String].self, forKey: .arguments) ?? []
        workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
        requiresAdministratorPrivileges = try container.decodeIfPresent(Bool.self, forKey: .requiresAdministratorPrivileges) ?? false
        environment = try container.decodeIfPresent([String: String].self, forKey: .environment) ?? [:]
        schedule = try container.decodeIfPresent(SchedulePreset.self, forKey: .schedule) ?? .manualOnly
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}

public struct RunRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var jobID: UUID
    public var jobName: String
    public var startedAt: Date
    public var finishedAt: Date
    public var exitCode: Int32
    public var stdoutPath: String?
    public var stderrPath: String?
    public var timedOut: Bool

    public var duration: TimeInterval { finishedAt.timeIntervalSince(startedAt) }

    public init(id: UUID = UUID(), jobID: UUID, jobName: String, startedAt: Date, finishedAt: Date, exitCode: Int32, stdoutPath: String?, stderrPath: String?, timedOut: Bool = false) {
        self.id = id
        self.jobID = jobID
        self.jobName = jobName
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.exitCode = exitCode
        self.stdoutPath = stdoutPath
        self.stderrPath = stderrPath
        self.timedOut = timedOut
    }
}
