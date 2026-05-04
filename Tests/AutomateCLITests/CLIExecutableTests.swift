import XCTest

final class CLIExecutableTests: XCTestCase {
    func testCLIAddListRunLogsSyncAndRemoveWithFriendlySchedules() throws {
        let dir = try temporaryDirectory()
        let store = dir.appendingPathComponent("jobs.json").path
        let script = dir.appendingPathComponent("success.sh")
        try """
        #!/bin/sh
        echo cli-smoke-ok
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        XCTAssertEqual(try runCLI(["--store", store, "--lang", "en", "add", "backup", "--cmd", script.path, "--daily", "09:00"]).status, 0)

        let edit = try runCLI(["--store", store, "--lang", "en", "edit", "backup", "--name", "backup2", "--every-minutes", "10"])
        XCTAssertEqual(edit.status, 0)
        XCTAssertTrue(edit.stdout.contains("Updated job 'backup2'."), edit.stdout + edit.stderr)

        let list = try runCLI(["--store", store, "--lang", "en", "list"])
        XCTAssertEqual(list.status, 0)
        XCTAssertTrue(list.stdout.contains("backup2 [enabled]"), list.stdout + list.stderr)
        XCTAssertTrue(list.stdout.contains("Every 10 minutes"), list.stdout + list.stderr)

        let run = try runCLI(["--store", store, "--lang", "en", "run", "backup2"])
        XCTAssertEqual(run.status, 0)
        XCTAssertTrue(run.stdout.contains("Run completed with exit code 0."), run.stdout + run.stderr)

        let logs = try runCLI(["--store", store, "logs", "backup2"])
        XCTAssertEqual(logs.status, 0)
        XCTAssertTrue(logs.stdout.contains("exit=0"), logs.stdout + logs.stderr)

        let sync = try runCLI(["--store", store, "--lang", "en", "sync", "--dry-run"])
        XCTAssertEqual(sync.status, 0)
        XCTAssertTrue(sync.stdout.contains("Dry run: create/update=1"), sync.stdout + sync.stderr)

        let applySync = try runCLI(["--store", store, "--lang", "en", "sync", "--apply"])
        XCTAssertEqual(applySync.status, 0, applySync.stdout + applySync.stderr)
        XCTAssertTrue(applySync.stdout.contains("dryRun=false"), applySync.stdout + applySync.stderr)
        let launchAgentsDir = dir.appendingPathComponent("LaunchAgents", isDirectory: true)
        let managedPlists = try FileManager.default.contentsOfDirectory(at: launchAgentsDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "plist" && $0.lastPathComponent.hasPrefix("com.alpox.automate-scripts.job") }
        XCTAssertEqual(managedPlists.count, 1)
        let plistData = try Data(contentsOf: try XCTUnwrap(managedPlists.first))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any])
        let programArguments = try XCTUnwrap(plist["ProgramArguments"] as? [String])
        XCTAssertEqual(Array(programArguments.prefix(4)), [productsDirectory().appendingPathComponent("automate").path, "--store", store, "run"])
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(programArguments.last)))
        XCTAssertNil(plist["StartInterval"])
        XCTAssertEqual(
            plist["StartCalendarInterval"] as? [[String: Int]],
            [["Minute": 0], ["Minute": 10], ["Minute": 20], ["Minute": 30], ["Minute": 40], ["Minute": 50]]
        )

        XCTAssertEqual(try runCLI(["--store", store, "remove", "backup2"]).status, 0)
    }

    func testCLIRejectsRawCronAndInvalidFriendlyPresetWithoutWritingStore() throws {
        let dir = try temporaryDirectory()
        let store = dir.appendingPathComponent("jobs.json").path

        let rawCron = try runCLI(["--store", store, "--lang", "en", "add", "cronjob", "--cmd", "/bin/echo", "--cron", "*/5 * * * *"])
        XCTAssertNotEqual(rawCron.status, 0)
        XCTAssertTrue(rawCron.stderr.contains("Raw cron expressions are not supported"), rawCron.stdout + rawCron.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store))

        let invalidDaily = try runCLI(["--store", store, "--lang", "en", "add", "badtime", "--cmd", "/bin/echo", "--daily", "99:99"])
        XCTAssertNotEqual(invalidDaily.status, 0)
        XCTAssertTrue(invalidDaily.stderr.contains("Invalid hour"), invalidDaily.stdout + invalidDaily.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store))

        let invalidInterval = try runCLI(["--store", store, "--lang", "en", "add", "badinterval", "--cmd", "/bin/echo", "--every-minutes", "1"])
        XCTAssertNotEqual(invalidInterval.status, 0)
        XCTAssertTrue(invalidInterval.stderr.contains("Unsupported interval"), invalidInterval.stdout + invalidInterval.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store))
    }


    func testCLIConfiguresAndOverridesInputAnswer() throws {
        let dir = try temporaryDirectory()
        let store = dir.appendingPathComponent("jobs.json").path
        let script = dir.appendingPathComponent("stdin.sh")
        try """
        #!/bin/sh
        read answer
        echo answer=$answer
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let add = try runCLI(["--store", store, "add", "stdinjob", "--cmd", script.path, "--answer", "hello", "--input-required"])
        XCTAssertEqual(add.status, 0, add.stdout + add.stderr)
        let storedJSON = try String(contentsOfFile: store, encoding: .utf8)
        XCTAssertTrue(storedJSON.contains("inputPolicy"), storedJSON)
        XCTAssertTrue(storedJSON.contains("hello"), storedJSON)

        let runDefault = try runCLI(["--store", store, "run", "stdinjob"])
        XCTAssertEqual(runDefault.status, 0, runDefault.stdout + runDefault.stderr)
        let defaultStdoutPath = try XCTUnwrap(runDefault.stdout.split(separator: "\n").first { $0.hasPrefix("stdout: ") }?.dropFirst("stdout: ".count))
        let defaultOutput = try String(contentsOfFile: String(defaultStdoutPath), encoding: .utf8)
        XCTAssertEqual(defaultOutput.trimmingCharacters(in: .whitespacesAndNewlines), "answer=hello")

        let runOverride = try runCLI(["--store", store, "run", "stdinjob", "--answer", "override"])
        XCTAssertEqual(runOverride.status, 0, runOverride.stdout + runOverride.stderr)
        let overrideStdoutPath = try XCTUnwrap(runOverride.stdout.split(separator: "\n").first { $0.hasPrefix("stdout: ") }?.dropFirst("stdout: ".count))
        let overrideOutput = try String(contentsOfFile: String(overrideStdoutPath), encoding: .utf8)
        XCTAssertEqual(overrideOutput.trimmingCharacters(in: .whitespacesAndNewlines), "answer=override")

        let editChoices = try runCLI(["--store", store, "edit", "stdinjob", "--no-input"])
        XCTAssertEqual(editChoices.status, 0, editChoices.stdout + editChoices.stderr)
        let addChoices = try runCLI([
            "--store", store, "edit", "stdinjob",
            "--answer-choice", "yes=y",
            "--answer-choice", "no=n",
            "--default-choice", "no",
            "--input-required"
        ])
        XCTAssertEqual(addChoices.status, 0, addChoices.stdout + addChoices.stderr)
        let runChoice = try runCLI(["--store", store, "run", "stdinjob", "--choice", "yes"])
        XCTAssertEqual(runChoice.status, 0, runChoice.stdout + runChoice.stderr)
        let choiceStdoutPath = try XCTUnwrap(runChoice.stdout.split(separator: "\n").first { $0.hasPrefix("stdout: ") }?.dropFirst("stdout: ".count))
        let choiceOutput = try String(contentsOfFile: String(choiceStdoutPath), encoding: .utf8)
        XCTAssertEqual(choiceOutput.trimmingCharacters(in: .whitespacesAndNewlines), "answer=y")
    }

    private func runCLI(_ arguments: [String]) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: productsDirectory().appendingPathComponent("automate").path)
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }

    private func productsDirectory() -> URL {
        #if os(macOS)
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        #endif
        return Bundle.main.bundleURL
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
