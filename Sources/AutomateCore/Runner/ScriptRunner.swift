import Foundation

public final class ScriptRunner: @unchecked Sendable {
    public var timeout: TimeInterval
    public let logStore: RunLogStore

    public init(timeout: TimeInterval = 60 * 60, logStore: RunLogStore = RunLogStore()) {
        self.timeout = timeout
        self.logStore = logStore
    }

    @discardableResult public func run(_ job: ScriptJob) throws -> RunRecord {
        let invocation = CommandLineParser.normalized(commandText: job.command, arguments: job.arguments)
        guard !CommandSafety.isBlocked(command: invocation.command, arguments: invocation.arguments) else {
            throw ScriptRunnerError.blockedCommand(CommandSafety.warnings(command: invocation.command, arguments: invocation.arguments).joined(separator: " "))
        }
        let output = try logStore.prepareOutputURLs(for: job)
        let started = Date()
        let process = Process()
        if job.requiresAdministratorPrivileges {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            if invocation.command == "sudo" {
                process.arguments = ["-n"] + invocation.arguments
            } else if invocation.command.contains("/") {
                process.arguments = ["-n", invocation.command] + invocation.arguments
            } else {
                process.arguments = ["-n", "/usr/bin/env", invocation.command] + invocation.arguments
            }
        } else if invocation.command.contains("/") {
            process.executableURL = URL(fileURLWithPath: invocation.command)
            process.arguments = invocation.arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [invocation.command] + invocation.arguments
        }
        let workingDirectory = try job.workingDirectory.map { URL(fileURLWithPath: $0) } ?? AppPaths.ensureDefaultWorkingDirectory()
        process.currentDirectoryURL = workingDirectory
        var environment = ProcessInfo.processInfo.environment
        job.environment.forEach { environment[$0.key] = $0.value }
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()

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
