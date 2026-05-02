import Foundation

public final class ScriptRunner: @unchecked Sendable {
    public var timeout: TimeInterval
    public let logStore: RunLogStore

    public init(timeout: TimeInterval = 60 * 60, logStore: RunLogStore = RunLogStore()) {
        self.timeout = timeout
        self.logStore = logStore
    }

    @discardableResult public func run(_ job: ScriptJob, inputSelection: ScriptRunInputSelection? = nil) throws -> RunRecord {
        let invocation = CommandLineParser.normalized(commandText: job.command, arguments: job.arguments)
        guard !CommandSafety.isBlocked(command: invocation.command, arguments: invocation.arguments) else {
            throw ScriptRunnerError.blockedCommand(CommandSafety.warnings(command: invocation.command, arguments: invocation.arguments).joined(separator: " "))
        }
        let prepared = try CommandPreparation.prepare(invocation: invocation, job: job, inputSelection: inputSelection)
        let output = try logStore.prepareOutputURLs(for: job)
        let started = Date()
        let process = Process()
        if job.requiresAdministratorPrivileges {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            if prepared.invocation.command == "sudo" {
                process.arguments = ["-n"] + prepared.invocation.arguments
            } else if prepared.invocation.command.contains("/") {
                process.arguments = ["-n", prepared.invocation.command] + prepared.invocation.arguments
            } else {
                process.arguments = ["-n", "/usr/bin/env", prepared.invocation.command] + prepared.invocation.arguments
            }
        } else if prepared.invocation.command.contains("/") {
            process.executableURL = URL(fileURLWithPath: prepared.invocation.command)
            process.arguments = prepared.invocation.arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [prepared.invocation.command] + prepared.invocation.arguments
        }
        let workingDirectory = try job.workingDirectory.map { URL(fileURLWithPath: $0) } ?? AppPaths.ensureDefaultWorkingDirectory()
        process.currentDirectoryURL = workingDirectory
        var environment = ProcessInfo.processInfo.environment
        prepared.environment.forEach { environment[$0.key] = $0.value }
        process.environment = CommandExecutionEnvironment.augmentedEnvironment(
            for: prepared.invocation,
            base: environment
        )

        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = prepared.standardInput.map { _ in Pipe() }
        process.standardOutput = stdout
        process.standardError = stderr
        if let stdin {
            process.standardInput = stdin
        }
        try process.run()
        if let input = prepared.standardInput, let data = input.data(using: .utf8), let stdin {
            stdin.fileHandleForWriting.write(data)
            try? stdin.fileHandleForWriting.close()
        }

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }
        let timedOut = semaphore.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            process.terminate()
            _ = semaphore.wait(timeout: .now() + 2)
        }

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        try stdoutData.write(to: output.stdout, options: [.atomic])
        try stderrData.write(to: output.stderr, options: [.atomic])

        let record = RunRecord(
            id: output.runID,
            jobID: job.id,
            jobName: job.name,
            startedAt: started,
            finishedAt: Date(),
            exitCode: timedOut ? -1 : process.terminationStatus,
            stdoutPath: output.stdout.path,
            stderrPath: output.stderr.path,
            timedOut: timedOut
        )
        try logStore.append(record)
        return record
    }
}

public enum ScriptRunnerError: Error, LocalizedError, Sendable {
    case blockedCommand(String)

    public var errorDescription: String? {
        switch self { case .blockedCommand(let reason): "Blocked command: \(reason)" }
    }
}
