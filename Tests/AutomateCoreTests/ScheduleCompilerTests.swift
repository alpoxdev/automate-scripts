import AutomateCore
import XCTest

final class ScheduleCompilerTests: XCTestCase {
    func testDailyCompilesToCalendarInterval() throws {
        let job = ScriptJob(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "daily", command: "/bin/echo", schedule: .daily(hour: 9, minute: 15))
        let spec = try XCTUnwrap(ScheduleCompiler.compile(job: job, logDirectory: "/tmp/logs"))
        XCTAssertEqual(spec.startCalendarInterval, [["Hour": 9, "Minute": 15]])
        XCTAssertNil(spec.startInterval)
    }

    func testManualOnlyDoesNotCompile() throws {
        let job = ScriptJob(name: "manual", command: "/bin/echo", schedule: .manualOnly)
        XCTAssertNil(try ScheduleCompiler.compile(job: job))
    }

    func testLaunchAgentSchedulerDryRunOnlyManagesOwnLabels() throws {
        let dir = try tempDir()
        let scheduler = LaunchAgentScheduler(launchAgentsDirectory: dir, logDirectory: dir.appendingPathComponent("logs"))
        let jobs = [ScriptJob(name: "hourly", command: "/bin/echo", schedule: .hourly(minute: 10))]
        let plan = try scheduler.sync(jobs: jobs, dryRun: true)
        XCTAssertEqual(plan.createdOrUpdated.count, 1)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }

    func testLaunchAgentSchedulerAppliedSyncWritesPlistAndRemovesOnlyManagedLabels() throws {
        let dir = try tempDir()
        let unmanaged = dir.appendingPathComponent("com.example.other.plist")
        try "not managed".write(to: unmanaged, atomically: true, encoding: .utf8)
        let logs = dir.appendingPathComponent("logs", isDirectory: true)
        let scheduler = LaunchAgentScheduler(launchAgentsDirectory: dir, logDirectory: logs)
        let job = ScriptJob(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            name: "hourly",
            command: "/bin/echo",
            arguments: ["hello"],
            schedule: .hourly(minute: 10)
        )

        let applyPlan = try scheduler.sync(jobs: [job], dryRun: false)
        XCTAssertEqual(applyPlan.createdOrUpdated.count, 1)
        let label = try XCTUnwrap(applyPlan.createdOrUpdated.first)
        XCTAssertTrue(label.hasPrefix(ScheduleCompiler.labelPrefix))
        let plistURL = dir.appendingPathComponent("\(label).plist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: plistURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unmanaged.path))

        let plistData = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any])
        XCTAssertEqual(plist["Label"] as? String, label)
        XCTAssertEqual(plist["ProgramArguments"] as? [String], ["/usr/bin/env", "/bin/echo", "hello"])
        XCTAssertEqual(plist["StartCalendarInterval"] as? [String: Int], ["Minute": 10])
        XCTAssertEqual(plist["StandardOutPath"] as? String, "\(logs.path)/\(job.id.uuidString)-stdout.log")
        XCTAssertEqual(plist["StandardErrorPath"] as? String, "\(logs.path)/\(job.id.uuidString)-stderr.log")

        let removePlan = try scheduler.sync(jobs: [], dryRun: false)
        XCTAssertEqual(removePlan.removed, [label])
        XCTAssertFalse(FileManager.default.fileExists(atPath: plistURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unmanaged.path))
    }

    func testLaunchAgentSchedulerReloadsServicesWhenRequested() throws {
        let dir = try tempDir()
        let logs = dir.appendingPathComponent("logs", isDirectory: true)
        let controller = RecordingLaunchController()
        let scheduler = LaunchAgentScheduler(
            launchAgentsDirectory: dir,
            logDirectory: logs,
            reloadServices: true,
            launchController: controller
        )
        let job = ScriptJob(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000321")!,
            name: "reloadable",
            command: "/bin/echo",
            schedule: .everyMinutes(5)
        )

        let applyPlan = try scheduler.sync(jobs: [job], dryRun: false)
        let label = try XCTUnwrap(applyPlan.createdOrUpdated.first)
        XCTAssertEqual(controller.bootedOutLabels, [label])
        XCTAssertEqual(controller.bootstrappedPlistURLs, [dir.appendingPathComponent("\(label).plist")])

        _ = try scheduler.sync(jobs: [], dryRun: false)
        XCTAssertEqual(controller.bootedOutLabels, [label, label])
    }

    func testLaunchAgentSchedulerSkipsReloadWhenSpecUnchanged() throws {
        let dir = try tempDir()
        let logs = dir.appendingPathComponent("logs", isDirectory: true)
        let controller = RecordingLaunchController()
        let scheduler = LaunchAgentScheduler(
            launchAgentsDirectory: dir,
            logDirectory: logs,
            reloadServices: true,
            launchController: controller
        )
        let job = ScriptJob(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000654")!,
            name: "stable",
            command: "/bin/echo",
            schedule: .hourly(minute: 0)
        )

        let firstPlan = try scheduler.sync(jobs: [job], dryRun: false)
        let label = try XCTUnwrap(firstPlan.createdOrUpdated.first)
        XCTAssertEqual(controller.bootstrappedPlistURLs.count, 1)
        XCTAssertEqual(controller.bootedOutLabels, [label])

        let plistURL = dir.appendingPathComponent("\(label).plist")
        let mtimeBefore = try FileManager.default.attributesOfItem(atPath: plistURL.path)[.modificationDate] as? Date

        let secondPlan = try scheduler.sync(jobs: [job], dryRun: false)
        XCTAssertTrue(secondPlan.createdOrUpdated.isEmpty)
        XCTAssertEqual(secondPlan.unchanged, [label])
        XCTAssertEqual(controller.bootstrappedPlistURLs.count, 1, "unchanged spec must not trigger bootstrap")
        XCTAssertEqual(controller.bootedOutLabels, [label], "unchanged spec must not trigger bootout")

        let mtimeAfter = try FileManager.default.attributesOfItem(atPath: plistURL.path)[.modificationDate] as? Date
        XCTAssertEqual(mtimeBefore, mtimeAfter, "plist must not be rewritten when content is unchanged")
    }

    func testCustomLaunchAgentDirectoryDoesNotReloadServicesByDefault() throws {
        let dir = try tempDir()
        let controller = RecordingLaunchController()
        let scheduler = LaunchAgentScheduler(
            launchAgentsDirectory: dir,
            logDirectory: dir.appendingPathComponent("logs"),
            launchController: controller
        )

        let job = ScriptJob(name: "local-only", command: "/bin/echo", schedule: .atLogin)
        _ = try scheduler.sync(jobs: [job], dryRun: false)

        XCTAssertTrue(controller.bootedOutLabels.isEmpty)
        XCTAssertTrue(controller.bootstrappedPlistURLs.isEmpty)
    }

    func testPrivilegedLaunchAgentUsesNonInteractiveSudoAndDefaultWorkspace() throws {
        let job = ScriptJob(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!,
            name: "root-task",
            command: "/usr/bin/id",
            requiresAdministratorPrivileges: true,
            schedule: .atLogin
        )

        let spec = try XCTUnwrap(ScheduleCompiler.compile(job: job))
        XCTAssertEqual(spec.programArguments, ["/usr/bin/sudo", "-n", "/usr/bin/id"])
        XCTAssertEqual(spec.workingDirectory, AppPaths.defaultWorkingDirectory().path)
    }

    func testLaunchAgentSplitsFullCommandBeforeSlashArgument() throws {
        let job = ScriptJob(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000100")!,
            name: "skills",
            command: "npx skills add alpoxdev/hypercore-business --skill '*' -g -y",
            schedule: .atLogin
        )

        let spec = try XCTUnwrap(ScheduleCompiler.compile(job: job))
        XCTAssertEqual(spec.programArguments, [
            "/usr/bin/env",
            "npx",
            "skills",
            "add",
            "alpoxdev/hypercore-business",
            "--skill",
            "*",
            "-g",
            "-y"
        ])
    }


    func testScheduledRequiredInputWithoutDefaultFailsFast() throws {
        let job = ScriptJob(
            name: "needs-input",
            command: "/bin/cat",
            inputPolicy: ScriptInputPolicy(requirement: .required),
            schedule: .atLogin
        )
        XCTAssertThrowsError(try ScheduleCompiler.compile(job: job)) { error in
            XCTAssertEqual(error as? ScriptInputResolutionError, .requiredAnswerMissing)
        }
    }

    func testScheduledInputDefaultUsesShellWrapper() throws {
        let job = ScriptJob(
            name: "scheduled-input",
            command: "/bin/sh",
            arguments: ["-c", "read answer; echo $answer"],
            inputPolicy: ScriptInputPolicy(requirement: .required, defaultAnswer: "hello"),
            schedule: .atLogin
        )

        let spec = try XCTUnwrap(ScheduleCompiler.compile(job: job))
        XCTAssertEqual(spec.programArguments.first, "/bin/sh")
        XCTAssertEqual(spec.programArguments.dropFirst().first, "-c")
        let shellCommand = try XCTUnwrap(spec.programArguments.last)
        XCTAssertTrue(shellCommand.contains("printf %s"), shellCommand)
        XCTAssertTrue(shellCommand.contains("hello"), shellCommand)
        XCTAssertTrue(shellCommand.contains("/usr/bin/env"), shellCommand)
        XCTAssertTrue(shellCommand.contains("exec '/usr/bin/env' '/bin/sh' '-c'"), shellCommand)
    }

    func testScheduledInputShellWrapperQuotesSingleQuotes() throws {
        let job = ScriptJob(
            name: "quoted-input",
            command: "/bin/cat",
            inputPolicy: ScriptInputPolicy(requirement: .required, defaultAnswer: "it\'s ok"),
            schedule: .atLogin
        )

        let spec = try XCTUnwrap(ScheduleCompiler.compile(job: job))
        let shellCommand = try XCTUnwrap(spec.programArguments.last)
        XCTAssertTrue(shellCommand.contains("'it'\\''s ok\n'"), shellCommand)
    }

    func testScheduledNpxAutoConfirmAddsYesAndEnvironment() throws {
        let job = ScriptJob(
            name: "npx-auto",
            command: "npx create-example",
            schedule: .atLogin
        )

        let spec = try XCTUnwrap(ScheduleCompiler.compile(job: job))
        XCTAssertEqual(spec.programArguments, ["/usr/bin/env", "npx", "--yes", "create-example"])
        XCTAssertEqual(spec.environment["npm_config_yes"], "true")
        XCTAssertTrue(spec.environment["PATH"]?.split(separator: ":").contains("/opt/homebrew/bin") == true)
        XCTAssertTrue(spec.environment["PATH"]?.split(separator: ":").contains("/usr/local/bin") == true)
    }

    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class RecordingLaunchController: LaunchAgentControlling, @unchecked Sendable {
    private(set) var bootstrappedPlistURLs: [URL] = []
    private(set) var bootedOutLabels: [String] = []

    func bootstrap(plistURL: URL) throws {
        bootstrappedPlistURLs.append(plistURL)
    }

    func bootout(label: String) throws {
        bootedOutLabels.append(label)
    }
}
