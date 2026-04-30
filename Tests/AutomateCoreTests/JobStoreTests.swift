import AutomateCore
import XCTest

final class JobStoreTests: XCTestCase {
    func testAddListUpdateRemove() throws {
        let dir = try temporaryDirectory()
        let store = JobStore(fileURL: dir.appendingPathComponent("jobs.json"))
        let job = ScriptJob(name: "backup", command: "/bin/echo", arguments: ["hi"], schedule: .daily(hour: 9, minute: 0))
        try store.add(job)
        XCTAssertEqual(try store.list().count, 1)
        var updated = try XCTUnwrap(store.find(nameOrID: "backup"))
        updated.enabled = false
        try store.update(updated)
        XCTAssertFalse(try XCTUnwrap(store.find(nameOrID: "backup")).enabled)
        let removed = try store.remove(nameOrID: "backup")
        XCTAssertEqual(removed.name, "backup")
        XCTAssertTrue(try store.list().isEmpty)
    }

    func testAtomicWriteCreatesBackup() throws {
        let dir = try temporaryDirectory()
        let store = JobStore(fileURL: dir.appendingPathComponent("jobs.json"))
        try store.add(ScriptJob(name: "one", command: "/bin/echo"))
        try store.add(ScriptJob(name: "two", command: "/bin/echo"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("jobs.bak").path))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
