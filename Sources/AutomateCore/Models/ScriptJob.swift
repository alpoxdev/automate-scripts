import Foundation

public struct ScriptAnswerChoice: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var label: String
    public var value: String

    public init(id: String? = nil, label: String, value: String) {
        self.label = label
        self.value = value
        self.id = id ?? Self.makeID(from: label)
    }

    private static func makeID(from label: String) -> String {
        let slug = label.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : "-"
        }.reduce("") { $0 + String($1) }
        let trimmed = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? UUID().uuidString : trimmed
    }
}

public enum ScriptInputRequirement: String, Codable, Equatable, Sendable {
    case none
    case optional
    case required
}

public struct ScriptRunInputSelection: Codable, Equatable, Sendable {
    public var answer: String?
    public var choiceID: String?
    public var choiceLabel: String?

    public init(answer: String? = nil, choiceID: String? = nil, choiceLabel: String? = nil) {
        self.answer = answer
        self.choiceID = choiceID
        self.choiceLabel = choiceLabel
    }
}

public struct ScriptInputPolicy: Codable, Equatable, Sendable {
    public var requirement: ScriptInputRequirement
    public var defaultAnswer: String?
    public var answerChoices: [ScriptAnswerChoice]
    public var defaultChoiceID: String?

    public init(
        requirement: ScriptInputRequirement = .none,
        defaultAnswer: String? = nil,
        answerChoices: [ScriptAnswerChoice] = [],
        defaultChoiceID: String? = nil
    ) {
        self.requirement = requirement
        self.defaultAnswer = defaultAnswer
        self.answerChoices = answerChoices
        self.defaultChoiceID = defaultChoiceID
    }

    public static let none = ScriptInputPolicy()

    public var hasInput: Bool {
        requirement != .none || defaultAnswer != nil || !answerChoices.isEmpty || defaultChoiceID != nil
    }

    public func resolvedAnswer(selection: ScriptRunInputSelection? = nil) throws -> String? {
        if let explicit = selection?.answer {
            return explicit
        }
        if let choiceID = selection?.choiceID {
            guard let choice = answerChoices.first(where: { $0.id == choiceID }) else {
                throw ScriptInputResolutionError.choiceNotFound(choiceID)
            }
            return choice.value
        }
        if let choiceLabel = selection?.choiceLabel {
            guard let choice = answerChoices.first(where: { $0.label == choiceLabel || $0.id == choiceLabel }) else {
                throw ScriptInputResolutionError.choiceNotFound(choiceLabel)
            }
            return choice.value
        }
        if let defaultChoiceID {
            guard let choice = answerChoices.first(where: { $0.id == defaultChoiceID || $0.label == defaultChoiceID }) else {
                throw ScriptInputResolutionError.choiceNotFound(defaultChoiceID)
            }
            return choice.value
        }
        if let defaultAnswer {
            return defaultAnswer
        }
        if requirement == .required {
            throw ScriptInputResolutionError.requiredAnswerMissing
        }
        return nil
    }
}

public enum ScriptInputResolutionError: Error, LocalizedError, Equatable, Sendable {
    case requiredAnswerMissing
    case choiceNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .requiredAnswerMissing:
            "This script requires an input answer, but no default or selected answer was provided."
        case .choiceNotFound(let choice):
            "Input answer choice not found: \(choice)"
        }
    }
}

public struct ScriptJob: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var description: String?
    public var command: String
    public var arguments: [String]
    public var workingDirectory: String?
    public var requiresAdministratorPrivileges: Bool
    public var environment: [String: String]
    public var inputPolicy: ScriptInputPolicy
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
        inputPolicy: ScriptInputPolicy = .none,
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
        self.inputPolicy = inputPolicy
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
        case inputPolicy
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
        inputPolicy = try container.decodeIfPresent(ScriptInputPolicy.self, forKey: .inputPolicy) ?? .none
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
