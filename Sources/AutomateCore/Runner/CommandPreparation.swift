import Foundation

public enum ScriptExecutionContext: Sendable {
    case manual
    case scheduled
}

public struct PreparedCommand: Equatable, Sendable {
    public var invocation: CommandInvocation
    public var environment: [String: String]
    public var standardInput: String?
    public var appliedAutomaticNPXConfirmation: Bool
}

public enum CommandPreparation {
    public static func prepare(
        invocation: CommandInvocation,
        job: ScriptJob,
        inputSelection: ScriptRunInputSelection? = nil,
        context: ScriptExecutionContext = .manual
    ) throws -> PreparedCommand {
        var preparedInvocation = invocation
        var environment = job.environment
        var automaticNPX = false

        if isNPXCommand(invocation.command), !hasYesFlag(invocation.arguments) {
            preparedInvocation.arguments = ["--yes"] + invocation.arguments
            if environment["npm_config_yes"] == nil {
                environment["npm_config_yes"] = "true"
            }
            automaticNPX = true
        }

        let answer = try job.inputPolicy.resolvedAnswer(selection: inputSelection)
        let standardInput = answer.map { value in
            value.hasSuffix("\n") ? value : "\(value)\n"
        }

        if context == .scheduled, job.inputPolicy.requirement == .required, standardInput == nil {
            throw ScriptInputResolutionError.requiredAnswerMissing
        }

        return PreparedCommand(
            invocation: preparedInvocation,
            environment: environment,
            standardInput: standardInput,
            appliedAutomaticNPXConfirmation: automaticNPX
        )
    }

    public static func isNPXCommand(_ command: String) -> Bool {
        URL(fileURLWithPath: command).lastPathComponent == "npx"
    }

    public static func hasYesFlag(_ arguments: [String]) -> Bool {
        arguments.contains { $0 == "-y" || $0 == "--yes" }
    }
}
