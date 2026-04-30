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

        let edit = try runCLI(["--store", store, "--lang", "en", "edit", "backup", "--name", "backup2", "--weekly", "mon", "08:30"])
        XCTAssertEqual(edit.status, 0)
        XCTAssertTrue(edit.stdout.contains("Updated job 'backup2'."), edit.stdout + edit.stderr)

        let list = try runCLI(["--store", store, "--lang", "ko", "list"])
        XCTAssertEqual(list.status, 0)
        XCTAssertTrue(list.stdout.contains("backup2 [enabled]"), list.stdout + list.stderr)
        XCTAssertTrue(list.stdout.contains("매주 월요일 08:30"), list.stdout + list.stderr)

        let run = try runCLI(["--store", store, "--lang", "en", "run", "backup2"])
        XCTAssertEqual(run.status, 0)
        XCTAssertTrue(run.stdout.contains("Run completed with exit code 0."), run.stdout + run.stderr)

        let logs = try runCLI(["--store", store, "logs", "backup2"])
        XCTAssertEqual(logs.status, 0)
        XCTAssertTrue(logs.stdout.contains("exit=0"), logs.stdout + logs.stderr)

        let sync = try runCLI(["--store", store, "--lang", "en", "sync", "--dry-run"])
        XCTAssertEqual(sync.status, 0)
        XCTAssertTrue(sync.stdout.contains("Dry run: create/update=1"), sync.stdout + sync.stderr)

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
