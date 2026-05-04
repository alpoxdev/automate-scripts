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

    func testEveryTenMinutesCompilesToCronAlignedCalendarMinutes() throws {
        let job = ScriptJob(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            name: "ten-minute-cron",
            command: "/bin/echo",
            schedule: .everyMinutes(10)
        )

        let spec = try XCTUnwrap(ScheduleCompiler.compile(job: job, logDirectory: "/tmp/logs"))
        XCTAssertNil(spec.startInterval)
        XCTAssertEqual(
            spec.startCalendarInterval,
            [["Minute": 0], ["Minute": 10], ["Minute": 20], ["Minute": 30], ["Minute": 40], ["Minute": 50]]
        )

        let plist = ScheduleCompiler.propertyListDictionary(for: spec)
        XCTAssertNil(plist["StartInterval"])
        XCTAssertEqual(
            plist["StartCalendarInterval"] as? [[String: Int]],
            [["Minute": 0], ["Minute": 10], ["Minute": 20], ["Minute": 30], ["Minute": 40], ["Minute": 50]]
        )
    }

    func testEveryMinutesPresetsUseCalendarBoundariesInsteadOfLoadRelativeIntervals() throws {
        let expectations: [(minutes: Int, boundaries: [[String: Int]])] = [
            (5, stride(from: 0, to: 60, by: 5).map { ["Minute": $0] }),
            (10, stride(from: 0, to: 60, by: 10).map { ["Minute": $0] }),
            (15, stride(from: 0, to: 60, by: 15).map { ["Minute": $0] }),
            (30, stride(from: 0, to: 60, by: 30).map { ["Minute": $0] })
        ]

        for expectation in expectations {
            let job = ScriptJob(name: "every-\(expectation.minutes)", command: "/bin/echo", schedule: .everyMinutes(expectation.minutes))
            let spec = try XCTUnwrap(ScheduleCompiler.compile(job: job))
            XCTAssertNil(spec.startInterval, "Every \(expectation.minutes) minutes must not be relative to launch/load time.")
            XCTAssertEqual(spec.startCalendarInterval, expectation.boundaries)
        }
    }

    func testLaunchAgentSchedulerDryRunOnlyManagesOwnLabels() throws {
        let dir = try tempDir()
        let storeURL = dir.appendingPathComponent("jobs.json")
        let runnerPath = dir.appendingPathComponent("automate").path
        let scheduler = LaunchAgentScheduler(
            launchAgentsDirectory: dir,
            runnerPath: runnerPath,
            storeURL: storeURL,
            logDirectory: dir.appendingPathComponent("logs")
        )
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
        let storeURL = dir.appendingPathComponent("jobs.json")
        let runnerPath = dir.appendingPathComponent("automate").path
        let scheduler = LaunchAgentScheduler(
            launchAgentsDirectory: dir,
            runnerPath: runnerPath,
            storeURL: storeURL,
            logDirectory: logs
        )
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
        XCTAssertEqual(plist["ProgramArguments"] as? [String], [runnerPath, "--store", storeURL.path, "run", job.id.uuidString])
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
        let storeURL = dir.appendingPathComponent("jobs.json")
        let scheduler = LaunchAgentScheduler(
            launchAgentsDirectory: dir,
            runnerPath: dir.appendingPathComponent("automate").path,
            storeURL: storeURL,
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
        let storeURL = dir.appendingPathComponent("jobs.json")
        let scheduler = LaunchAgentScheduler(
            launchAgentsDirectory: dir,
            runnerPath: dir.appendingPathComponent("automate").path,
            storeURL: storeURL,
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
            runnerPath: dir.appendingPathComponent("automate").path,
            storeURL: dir.appendingPathComponent("jobs.json"),
            logDirectory: dir.appendingPathComponent("logs"),
            launchController: controller
        )

        let job = ScriptJob(name: "local-only", command: "/bin/echo", schedule: .atLogin)
        _ = try scheduler.sync(jobs: [job], dryRun: false)

        XCTAssertTrue(controller.bootedOutLabels.isEmpty)
        XCTAssertTrue(controller.bootstrappedPlistURLs.isEmpty)
    }

    func testScheduledLaunchAgentUsesAutomateRunnerAndDefaultWorkspace() throws {
        let job = ScriptJob(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!,
            name: "root-task",
            command: "/usr/bin/id",
            requiresAdministratorPrivileges: true,
            schedule: .atLogin
        )

        let runnerPath = "/Applications/Automate Scripts.app/Contents/MacOS/automate"
        let storePath = "/Users/example/Library/Application Support/AutomateScripts/jobs.json"
        let spec = try XCTUnwrap(ScheduleCompiler.compile(job: job, runnerPath: runnerPath, storePath: storePath))
        XCTAssertEqual(spec.programArguments, [runnerPath, "--store", storePath, "run", job.id.uuidString])
        XCTAssertEqual(spec.workingDirectory, AppPaths.defaultWorkingDirectory().path)
    }

    func testScheduledLaunchAgentUsesJobIDInsteadOfInliningCommand() throws {
        let job = ScriptJob(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000100")!,
            name: "skills",
            command: "npx skills add alpoxdev/hypercore-business --skill '*' -g -y",
            schedule: .atLogin
        )

        let runnerPath = "/Applications/Automate Scripts.app/Contents/MacOS/automate"
        let storePath = "/tmp/jobs.json"
        let spec = try XCTUnwrap(ScheduleCompiler.compile(job: job, runnerPath: runnerPath, storePath: storePath))
        XCTAssertEqual(spec.programArguments, [runnerPath, "--store", storePath, "run", job.id.uuidString])
        XCTAssertFalse(spec.programArguments.contains("npx"))
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

    func testScheduledInputDefaultRoutesThroughAutomateRunner() throws {
        let job = ScriptJob(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000190")!,
            name: "scheduled-input",
            command: "/bin/sh",
            arguments: ["-c", "read answer; echo $answer"],
            inputPolicy: ScriptInputPolicy(requirement: .required, defaultAnswer: "hello"),
            schedule: .atLogin
        )

        let runnerPath = "/Applications/Automate Scripts.app/Contents/MacOS/automate"
        let storePath = "/tmp/jobs.json"
        let spec = try XCTUnwrap(ScheduleCompiler.compile(job: job, runnerPath: runnerPath, storePath: storePath))
        XCTAssertEqual(spec.programArguments, [runnerPath, "--store", storePath, "run", job.id.uuidString])
    }

    func testScheduledInputDefaultDoesNotInlineAnswerInPlist() throws {
        let job = ScriptJob(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000191")!,
            name: "quoted-input",
            command: "/bin/cat",
            inputPolicy: ScriptInputPolicy(requirement: .required, defaultAnswer: "it\'s ok"),
            schedule: .atLogin
        )

        let spec = try XCTUnwrap(ScheduleCompiler.compile(job: job, runnerPath: "/app/automate", storePath: "/tmp/jobs.json"))
        XCTAssertFalse(spec.programArguments.contains("it\'s ok\n"))
    }

    func testScheduledNpxAutoConfirmAddsYesAndEnvironment() throws {
        let job = ScriptJob(
            name: "npx-auto",
            command: "npx create-example",
            schedule: .atLogin
        )

        let spec = try XCTUnwrap(ScheduleCompiler.compile(job: job, runnerPath: "/app/automate", storePath: "/tmp/jobs.json"))
        XCTAssertEqual(spec.programArguments, ["/app/automate", "--store", "/tmp/jobs.json", "run", job.id.uuidString])
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
