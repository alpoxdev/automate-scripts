import Foundation

public struct RunNotificationPayload: Equatable, Sendable {
    public var identifier: String
    public var title: String
    public var body: String
    public var playsSound: Bool

    public init(identifier: String, title: String, body: String, playsSound: Bool = true) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.playsSound = playsSound
    }
}

public enum RunNotificationPayloadBuilder: Sendable {
    public static func finished(record: RunRecord, localizer: Localizer) -> RunNotificationPayload {
        let (titleKey, bodyKey) = if record.timedOut {
            ("notification.runFailure.title", "notification.runTimedOut.body")
        } else if record.exitCode == 0 {
            ("notification.runSuccess.title", "notification.runSuccess.body")
        } else {
            ("notification.runFailure.title", "notification.runFailure.body")
        }

        return RunNotificationPayload(
            identifier: "run-finished-\(record.id.uuidString)",
            title: String(format: localizer.text(titleKey), record.jobName),
            body: String(format: localizer.text(bodyKey), record.jobName, Int(record.exitCode))
        )
    }

    public static func startFailed(job: ScriptJob, error: any Error, localizer: Localizer) -> RunNotificationPayload {
        RunNotificationPayload(
            identifier: "run-start-failed-\(job.id.uuidString)-\(UUID().uuidString)",
            title: String(format: localizer.text("notification.runStartFailed.title"), job.name),
            body: String(format: localizer.text("notification.runStartFailed.body"), job.name, error.localizedDescription)
        )
    }
}
