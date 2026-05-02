import AutomateCore
import UserNotifications

@MainActor
final class RunNotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let center: UNUserNotificationCenter
    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        self.center.delegate = self
    }

    func notifyRunFinished(record: RunRecord, localizer: Localizer) {
        let payload = RunNotificationPayloadBuilder.finished(record: record, localizer: localizer)
        deliver(payload)
    }

    func notifyRunStartFailed(job: ScriptJob, error: any Error, localizer: Localizer) {
        let payload = RunNotificationPayloadBuilder.startFailed(job: job, error: error, localizer: localizer)
        deliver(payload)
    }

    private func deliver(_ payload: RunNotificationPayload) {
        Task { @MainActor in
            guard await Self.ensureAuthorization(center: center) else { return }

            let content = UNMutableNotificationContent()
            content.title = payload.title
            content.body = payload.body
            if payload.playsSound {
                content.sound = .default
            }

            let request = UNNotificationRequest(identifier: payload.identifier, content: content, trigger: nil)
            do {
                try await center.add(request)
            } catch {
                // Notifications must never break script execution state updates.
            }
        }
    }

    private static func ensureAuthorization(center: UNUserNotificationCenter) async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
