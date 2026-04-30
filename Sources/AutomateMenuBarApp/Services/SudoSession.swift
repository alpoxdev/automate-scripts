import AutomateCore
import Foundation
import PrivilegedExecutionShim
import Security

actor SudoSession {
    private let privilegedShell = "/bin/sh"
    private var authorization: AuthorizationRef?
    private var authorized = false

    var isAuthorized: Bool {
        authorized
    }

    func ensureAuthorized() async throws {
        try authorizeIfNeeded()
    }

    func run(_ job: ScriptJob, logStore: RunLogStore, timeout: TimeInterval = 60 * 60) async throws -> RunRecord {
        let invocation = CommandLineParser.normalized(commandText: job.command, arguments: job.arguments)
        guard !CommandSafety.isBlocked(command: invocation.command, arguments: invocation.arguments) else {
            throw ScriptRunnerError.blockedCommand(CommandSafety.warnings(command: invocation.command, arguments: invocation.arguments).joined(separator: " "))
        }

        let output = try logStore.prepareOutputURLs(for: job)
        let exitURL = output.stdout.deletingPathExtension().appendingPathExtension("exit")
        try? FileManager.default.removeItem(at: exitURL)
        try? Data().write(to: output.stdout, options: [.atomic])
        try? Data().write(to: output.stderr, options: [.atomic])

        let started = Date()
        let workingDirectory = try job.workingDirectory.map { URL(fileURLWithPath: $0) } ?? AppPaths.ensureDefaultWorkingDirectory()
        let script = Self.privilegedShellScript(
            invocation: invocation,
            environment: job.environment,
            workingDirectory: workingDirectory,
            stdoutURL: output.stdout,
            stderrURL: output.stderr,
            exitURL: exitURL
        )

        try authorizeIfNeeded()
        let exitCode = try await executePrivilegedShell(script: script, exitURL: exitURL, stderrURL: output.stderr, timeout: timeout)
        let timedOut = exitCode == -1

        let record = RunRecord(
            id: output.runID,
            jobID: job.id,
            jobName: job.name,
            startedAt: started,
            finishedAt: Date(),
            exitCode: exitCode,
            stdoutPath: output.stdout.path,
            stderrPath: output.stderr.path,
            timedOut: timedOut
        )
        try logStore.append(record)
        return record
    }

    private func authorizeIfNeeded() throws {
        if authorized, authorization != nil {
            return
        }

        let prompt = "Automate Scripts needs administrator privileges to run selected scripts."
        var authRef = authorization

        let status = privilegedShell.withCString { toolPath in
            prompt.withCString { promptPointer in
                kAuthorizationRightExecute.withCString { executeRight in
                    kAuthorizationEnvironmentPrompt.withCString { promptName in
                        var right = AuthorizationItem(
                            name: executeRight,
                            valueLength: strlen(toolPath),
                            value: UnsafeMutableRawPointer(mutating: toolPath),
                            flags: 0
                        )
                        var environmentItem = AuthorizationItem(
                            name: promptName,
                            valueLength: strlen(promptPointer),
                            value: UnsafeMutableRawPointer(mutating: promptPointer),
                            flags: 0
                        )

                        return withUnsafeMutablePointer(to: &right) { rightPointer in
                            var rights = AuthorizationRights(count: 1, items: rightPointer)
                            return withUnsafeMutablePointer(to: &environmentItem) { environmentPointer in
                                var environment = AuthorizationEnvironment(count: 1, items: environmentPointer)
                                return AuthorizationCreate(
                                    &rights,
                                    &environment,
                                    [.interactionAllowed, .extendRights, .preAuthorize],
                                    &authRef
                                )
                            }
                        }
                    }
                }
            }
        }

        guard status == errAuthorizationSuccess, let authRef else {
            throw SudoSessionError.authorizationFailed(Self.authorizationMessage(for: status))
        }

        authorization = authRef
        authorized = true
    }

    private func executePrivilegedShell(script: String, exitURL: URL, stderrURL: URL, timeout: TimeInterval) async throws -> Int32 {
        guard let authorization else {
            throw SudoSessionError.authorizationFailed("Administrator authorization is not ready.")
        }

        let launchStatus = try executeWithPrivileges(arguments: ["-c", script], authorization: authorization)
        guard launchStatus == errAuthorizationSuccess else {
            throw SudoSessionError.authorizationFailed(Self.authorizationMessage(for: launchStatus))
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: exitURL.path) {
                let text = (try? String(contentsOf: exitURL, encoding: .utf8))?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return Int32(text ?? "") ?? 1
            }
            try await Task.sleep(for: .milliseconds(100))
        }

        let message = "\nAutomate Scripts timed out waiting for privileged command completion after \(Int(timeout)) seconds.\n"
        if let data = message.data(using: .utf8), let handle = try? FileHandle(forWritingTo: stderrURL) {
            _ = try? handle.seekToEnd()
            _ = try? handle.write(contentsOf: data)
            _ = try? handle.close()
        }
        return -1
    }

    private func executeWithPrivileges(arguments: [String], authorization: AuthorizationRef) throws -> OSStatus {
        var cArguments: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) }
        defer {
            cArguments.compactMap { $0 }.forEach { free($0) }
        }
        cArguments.append(nil)

        return privilegedShell.withCString { shellPath in
            cArguments.withUnsafeMutableBufferPointer { buffer in
                AutomateAuthorizationExecuteWithPrivileges(authorization, shellPath, buffer.baseAddress!)
            }
        }
    }

    private static func privilegedShellScript(
        invocation: CommandInvocation,
        environment envVars: [String: String],
        workingDirectory: URL,
        stdoutURL: URL,
        stderrURL: URL,
        exitURL: URL
    ) -> String {
        let tokens = invocation.command == "sudo" ? invocation.arguments : [invocation.command] + invocation.arguments
        let environment = envVars
            .sorted { $0.key < $1.key }
            .map { shellQuote("\($0.key)=\($0.value)") }
            .joined(separator: " ")
        let envPrefix = environment.isEmpty ? "/usr/bin/env" : "/usr/bin/env \(environment)"
        let command = ([envPrefix] + tokens.map(shellQuote)).joined(separator: " ")

        return """
        cd \(shellQuote(workingDirectory.path)) || exit 125
        \(command) > \(shellQuote(stdoutURL.path)) 2> \(shellQuote(stderrURL.path))
        status=$?
        printf "%s" "$status" > \(shellQuote(exitURL.path))
        exit "$status"
        """
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func authorizationMessage(for status: OSStatus) -> String {
        SecCopyErrorMessageString(status, nil) as String? ?? "Authorization failed with status \(status)."
    }
}

enum SudoSessionError: Error, LocalizedError {
    case authorizationFailed(String)

    var errorDescription: String? {
        switch self {
        case .authorizationFailed(let message):
            return message
        }
    }
}
