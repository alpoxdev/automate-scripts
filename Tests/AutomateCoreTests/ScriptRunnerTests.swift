import AutomateCore
import XCTest

final class ScriptRunnerTests: XCTestCase {
    func testCommandLineParserSplitsFullCommandWithQuotedWildcardAndSlashArgument() {
        let invocation = CommandLineParser.normalized(commandText: "npx skills add alpoxdev/hypercore-business --skill '*' -g -y")
        XCTAssertEqual(invocation.command, "npx")
        XCTAssertEqual(invocation.arguments, ["skills", "add", "alpoxdev/hypercore-business", "--skill", "*", "-g", "-y"])
    }

    func testRunnerTreatsSlashInsideArgumentAsArgumentNotExecutablePath() throws {
        let dir = try tempDir()
        let bin = dir.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let npx = bin.appendingPathComponent("npx")
        try """
        #!/bin/sh
        printf '%s\\n' "$@"
        """.write(to: npx, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: npx.path)

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(bin.path):\(environment["PATH"] ?? "")"
        let job = ScriptJob(
            name: "skills",
            command: "npx skills add alpoxdev/hypercore-business --skill '*' -g -y",
            workingDirectory: dir.path,
            environment: environment
        )

        let record = try ScriptRunner(logStore: RunLogStore(directory: dir)).run(job)
        XCTAssertEqual(record.exitCode, 0)
        let stdout = try String(contentsOfFile: XCTUnwrap(record.stdoutPath), encoding: .utf8)
        XCTAssertTrue(stdout.contains("alpoxdev/hypercore-business"), stdout)
        XCTAssertTrue(stdout.contains("*"), stdout)
    }

    func testCapturesOutputAndExitCode() throws {
        let dir = try tempDir()
        let job = ScriptJob(name: "echo", command: "/bin/echo", arguments: ["hello"], workingDirectory: dir.path)
        let record = try ScriptRunner(logStore: RunLogStore(directory: dir)).run(job)
        XCTAssertEqual(record.exitCode, 0)
        let stdout = try String(contentsOfFile: XCTUnwrap(record.stdoutPath), encoding: .utf8)
        XCTAssertTrue(stdout.contains("hello"))
        XCTAssertEqual(try RunLogStore(directory: dir).records(for: job.id).count, 1)
    }

    func testRunLogFilesAreGroupedByJobFolder() throws {
        let dir = try tempDir()
        let job = ScriptJob(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000777")!,
            name: "daily backup",
            command: "/bin/echo",
            arguments: ["hello"],
            workingDirectory: dir.path
        )

        let record = try ScriptRunner(logStore: RunLogStore(directory: dir)).run(job)
        let stdoutPath = try XCTUnwrap(record.stdoutPath)
        let stderrPath = try XCTUnwrap(record.stderrPath)

        XCTAssertTrue(stdoutPath.contains("/daily-backup-\(job.id.uuidString)/"), stdoutPath)
        XCTAssertTrue(stderrPath.contains("/daily-backup-\(job.id.uuidString)/"), stderrPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stdoutPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stderrPath))
    }

    func testBlocksClearlyDestructiveCommand() throws {
        let job = ScriptJob(name: "bad", command: "rm", arguments: ["-rf", "/"])
        XCTAssertThrowsError(try ScriptRunner(logStore: RunLogStore(directory: try tempDir())).run(job))
    }

    func testMissingWorkingDirectoryUsesAppWorkspace() throws {
        let dir = try tempDir()
        let job = ScriptJob(name: "pwd", command: "/bin/pwd")
        let record = try ScriptRunner(logStore: RunLogStore(directory: dir)).run(job)
        let stdout = try String(contentsOfFile: XCTUnwrap(record.stdoutPath), encoding: .utf8)
        XCTAssertEqual(stdout.trimmingCharacters(in: .whitespacesAndNewlines), AppPaths.defaultWorkingDirectory().path)
    }

    func testOlderJobJSONDefaultsSudoFlagToFalse() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "name": "legacy",
          "command": "/bin/echo",
          "arguments": ["ok"],
          "environment": {},
          "schedule": { "kind": "manualOnly" },
          "enabled": true,
          "tags": [],
          "createdAt": "2026-04-30T00:00:00Z",
          "updatedAt": "2026-04-30T00:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let job = try decoder.decode(ScriptJob.self, from: json)
        XCTAssertFalse(job.requiresAdministratorPrivileges)
    }

    func testStashesOldRunRecordsAndMovesLogFiles() throws {
        let dir = try tempDir()
        let store = RunLogStore(directory: dir)
        let jobID = UUID()
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        let recentDate = oldDate.addingTimeInterval(10 * 24 * 60 * 60)
        let oldStdout = dir.appendingPathComponent("old.stdout.log")
        let oldStderr = dir.appendingPathComponent("old.stderr.log")
        try "old out".write(to: oldStdout, atomically: true, encoding: .utf8)
        try "old err".write(to: oldStderr, atomically: true, encoding: .utf8)

        try store.append(RunRecord(jobID: jobID, jobName: "old", startedAt: oldDate, finishedAt: oldDate, exitCode: 0, stdoutPath: oldStdout.path, stderrPath: oldStderr.path))
        try store.append(RunRecord(jobID: jobID, jobName: "recent", startedAt: recentDate, finishedAt: recentDate, exitCode: 0, stdoutPath: nil, stderrPath: nil))

        let summary = try store.stashLogs(olderThanDays: 7, now: recentDate)
        XCTAssertEqual(summary.stashedRuns, 1)
        XCTAssertEqual(try store.records(for: jobID).map(\.jobName), ["recent"])
        let stashed = try store.stashedRecords(for: jobID)
        XCTAssertEqual(stashed.map(\.jobName), ["old"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldStdout.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldStderr.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(stashed.first?.stdoutPath)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(stashed.first?.stderrPath)))
    }


    func testInputPolicyRoundTripAndLegacyDefault() throws {
        let legacyJSON = """
        {
          "id": "00000000-0000-0000-0000-000000000101",
          "name": "legacy-input",
          "command": "/bin/echo",
          "arguments": ["ok"],
          "environment": {},
          "schedule": { "kind": "manualOnly" },
          "enabled": true,
          "tags": [],
          "createdAt": "2026-04-30T00:00:00Z",
          "updatedAt": "2026-04-30T00:00:00Z"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let legacy = try decoder.decode(ScriptJob.self, from: legacyJSON)
        XCTAssertEqual(legacy.inputPolicy, .none)

        let job = ScriptJob(
            name: "answers",
            command: "/bin/cat",
            inputPolicy: ScriptInputPolicy(
                requirement: .required,
                defaultAnswer: "fallback",
                answerChoices: [ScriptAnswerChoice(label: "yes", value: "y")],
                defaultChoiceID: "yes"
            )
        )
        let encoded = try JSONEncoder().encode(job)
        let decoded = try JSONDecoder().decode(ScriptJob.self, from: encoded)
        XCTAssertEqual(decoded.inputPolicy.requirement, .required)
        XCTAssertEqual(decoded.inputPolicy.defaultAnswer, "fallback")
        XCTAssertEqual(decoded.inputPolicy.answerChoices.first?.value, "y")
    }

    func testRunnerSendsDefaultAnswerToStandardInput() throws {
        let dir = try tempDir()
        let job = ScriptJob(
            name: "stdin",
            command: "/bin/sh",
            arguments: ["-c", "read answer; printf 'answer=%s\\n' \"$answer\""],
            workingDirectory: dir.path,
            inputPolicy: ScriptInputPolicy(requirement: .required, defaultAnswer: "hello")
        )

        let record = try ScriptRunner(logStore: RunLogStore(directory: dir)).run(job)
        XCTAssertEqual(record.exitCode, 0)
        let stdout = try String(contentsOfFile: XCTUnwrap(record.stdoutPath), encoding: .utf8)
        XCTAssertEqual(stdout.trimmingCharacters(in: .whitespacesAndNewlines), "answer=hello")
    }

    func testRunnerUsesSelectedChoiceForStandardInput() throws {
        let dir = try tempDir()
        let job = ScriptJob(
            name: "stdin-choice",
            command: "/bin/sh",
            arguments: ["-c", "read answer; printf 'choice=%s\\n' \"$answer\""],
            workingDirectory: dir.path,
            inputPolicy: ScriptInputPolicy(
                requirement: .required,
                answerChoices: [
                    ScriptAnswerChoice(label: "yes", value: "y"),
                    ScriptAnswerChoice(label: "no", value: "n")
                ],
                defaultChoiceID: "no"
            )
        )

        let record = try ScriptRunner(logStore: RunLogStore(directory: dir)).run(job, inputSelection: ScriptRunInputSelection(choiceLabel: "yes"))
        XCTAssertEqual(record.exitCode, 0)
        let stdout = try String(contentsOfFile: XCTUnwrap(record.stdoutPath), encoding: .utf8)
        XCTAssertEqual(stdout.trimmingCharacters(in: .whitespacesAndNewlines), "choice=y")
    }

    func testRunnerThrowsWhenRequiredInputIsMissing() throws {
        let job = ScriptJob(
            name: "missing-input",
            command: "/bin/cat",
            inputPolicy: ScriptInputPolicy(requirement: .required)
        )
        XCTAssertThrowsError(try ScriptRunner(logStore: RunLogStore(directory: try tempDir())).run(job)) { error in
            XCTAssertEqual(error as? ScriptInputResolutionError, .requiredAnswerMissing)
        }
    }

    func testNpxAutoConfirmationAddsYesAndEnvironment() throws {
        let job = ScriptJob(name: "npx", command: "npx", arguments: ["create-example"])
        let prepared = try CommandPreparation.prepare(invocation: CommandInvocation(command: "npx", arguments: job.arguments), job: job)
        XCTAssertEqual(prepared.invocation.arguments, ["--yes", "create-example"])
        XCTAssertEqual(prepared.environment["npm_config_yes"], "true")
        XCTAssertTrue(prepared.appliedAutomaticNPXConfirmation)
    }

    func testNpxAutoConfirmationPreservesExistingYesFlag() throws {
        let job = ScriptJob(name: "npx", command: "npx", arguments: ["create-example", "-y"])
        let prepared = try CommandPreparation.prepare(invocation: CommandInvocation(command: "npx", arguments: job.arguments), job: job)
        XCTAssertEqual(prepared.invocation.arguments, ["create-example", "-y"])
        XCTAssertNil(prepared.environment["npm_config_yes"])
        XCTAssertFalse(prepared.appliedAutomaticNPXConfirmation)
    }

    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
