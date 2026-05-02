import AutomateCore
import XCTest

final class NotificationPayloadBuilderTests: XCTestCase {
    func testSuccessPayloadIncludesJobNameAndExitCode() {
        let record = makeRecord(jobName: "backup", exitCode: 0)
        let payload = RunNotificationPayloadBuilder.finished(record: record, localizer: Localizer(language: .english))

        XCTAssertEqual(payload.identifier, "run-finished-\(record.id.uuidString)")
        XCTAssertEqual(payload.title, "backup finished")
        XCTAssertEqual(payload.body, "backup completed successfully with exit code 0.")
        XCTAssertTrue(payload.playsSound)
    }

    func testFailurePayloadIncludesJobNameAndExitCode() {
        let record = makeRecord(jobName: "cleanup", exitCode: 2)
        let payload = RunNotificationPayloadBuilder.finished(record: record, localizer: Localizer(language: .english))

        XCTAssertEqual(payload.title, "cleanup failed")
        XCTAssertEqual(payload.body, "cleanup finished with exit code 2.")
    }

    func testTimedOutPayloadUsesTimeoutSpecificCopy() {
        let record = makeRecord(jobName: "sync", exitCode: -1, timedOut: true)
        let payload = RunNotificationPayloadBuilder.finished(record: record, localizer: Localizer(language: .english))

        XCTAssertEqual(payload.title, "sync failed")
        XCTAssertEqual(payload.body, "sync timed out before completion with exit code -1.")
    }

    func testStartFailedPayloadIncludesErrorText() {
        let job = ScriptJob(id: UUID(uuidString: "00000000-0000-0000-0000-000000000321")!, name: "deploy", command: "/missing")
        let payload = RunNotificationPayloadBuilder.startFailed(
            job: job,
            error: TestError(message: "permission denied"),
            localizer: Localizer(language: .english)
        )

        XCTAssertTrue(payload.identifier.hasPrefix("run-start-failed-\(job.id.uuidString)-"))
        XCTAssertEqual(payload.title, "deploy could not start")
        XCTAssertEqual(payload.body, "deploy could not start: permission denied")
    }

    func testKoreanPayloadUsesLocalizedCopy() {
        let record = makeRecord(jobName: "백업", exitCode: 0)
        let payload = RunNotificationPayloadBuilder.finished(record: record, localizer: Localizer(language: .korean))

        XCTAssertEqual(payload.title, "백업 완료")
        XCTAssertEqual(payload.body, "백업 작업이 종료 코드 0로 성공했습니다.")
    }

    private func makeRecord(jobName: String, exitCode: Int32, timedOut: Bool = false) -> RunRecord {
        RunRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            jobID: UUID(uuidString: "00000000-0000-0000-0000-000000000456")!,
            jobName: jobName,
            startedAt: Date(timeIntervalSince1970: 1),
            finishedAt: Date(timeIntervalSince1970: 2),
            exitCode: exitCode,
            stdoutPath: nil,
            stderrPath: nil,
            timedOut: timedOut
        )
    }
}

private struct TestError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
