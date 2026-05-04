import AutomateCore
import AppKit
import SwiftUI

@main
struct AutomateMenuBarApp: App {
    @StateObject private var model = MenuBarModel()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        Self.configureApplicationIcon()
    }

    private static func configureApplicationIcon() {
        let image = NSImage(named: "AutomateScriptsLogo") ?? NSImage(named: "AutomateScripts")
        if let image {
            NSApplication.shared.applicationIconImage = image
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarRootView(model: model)
                .frame(width: 460, height: 560)
        } label: {
            MenuBarStatusIcon(hasFailures: model.hasFailures, title: model.statusTitle)
        }
        .menuBarExtraStyle(.window)
        Settings {
            SettingsView(model: model)
        }
    }
}

private struct MenuBarStatusIcon: View {
    let hasFailures: Bool
    let title: String

    var body: some View {
        Group {
            if hasFailures {
                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.hierarchical)
            } else {
                Image(nsImage: Self.templateIcon())
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: 20, height: 20)
            }
        }
        .accessibilityLabel(Text(title))
    }

    private static func templateIcon() -> NSImage {
        let image = (NSImage(named: "MenuBarIcon") ?? NSImage(size: NSSize(width: 20, height: 20))).copy() as? NSImage
        image?.isTemplate = false
        image?.size = NSSize(width: 20, height: 20)
        return image ?? NSImage(size: NSSize(width: 20, height: 20))
    }
}

@MainActor
enum AppUpdateState {
    case idle
    case checking
    case upToDate(String)
    case available(release: GitHubRelease, asset: GitHubReleaseAsset)
    case noCompatibleAsset(String)
    case developmentBuild(String)
    case installing(String)
    case restarting
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .checking, .installing, .restarting: true
        default: false
        }
    }
}

@MainActor
final class MenuBarModel: ObservableObject {
    @Published var jobs: [ScriptJob] = []
    @Published var latestRecords: [UUID: RunRecord] = [:]
    @Published var runningJobIDs: Set<UUID> = []
    @Published var lastMessage: String = ""
    @Published var language: AppLanguage = .system()
    @Published var settings: AppSettings
    @Published var updateState: AppUpdateState = .idle
    @Published var lastUpdateCheckedAt: Date?

    static let updateCheckInterval: TimeInterval = 60 * 60
    static let runLogRefreshInterval: TimeInterval = 30
    private var updateCheckTimer: Timer?
    private var runLogRefreshTimer: Timer?

    let store = JobStore()
    let logStore = RunLogStore()
    let settingsStore = AppSettingsStore()
    let appVersion = AppVersion.current()
    private let runner = ScriptRunner()
    private let scheduler = LaunchAgentScheduler()
    private let sudoSession = SudoSession()
    private let releaseUpdater = GitHubReleaseUpdater()
    private let updateInstaller = AppRelaunchInstaller()
    private let notificationService = RunNotificationService()

    var localizer: Localizer { Localizer(language: language) }
    var hasFailures: Bool { latestRecords.values.contains { $0.exitCode != 0 || $0.timedOut } }
    var enabledCount: Int { jobs.filter(\.enabled).count }
    var failureCount: Int { latestRecords.values.filter { $0.exitCode != 0 || $0.timedOut }.count }
    var runningCount: Int { runningJobIDs.count }
    var statusTitle: String { jobs.isEmpty ? localizer.text("app.name") : "\(localizer.text("app.name")) (\(jobs.count))" }
    var displayMessage: String { lastMessage.isEmpty ? localizer.text("status.ready") : lastMessage }
    var storePath: String { store.fileURL.path }
    var logPath: String { logStore.directory.path }
    var stashPath: String { logStore.stashDirectory.path }

    init() {
        settings = (try? settingsStore.load()) ?? AppSettings()
        try? settingsStore.save(settings)
        applyBackgroundMode()
        performLogMaintenance(showMessage: false)
        reload()
        do {
            try syncScheduler()
        } catch {
            lastMessage = error.localizedDescription
        }
        authorizeSavedPrivilegedJobsIfNeeded()
        checkForUpdates()
        startUpdateCheckTimer()
        startRunLogRefreshTimer()
    }

    private func startUpdateCheckTimer() {
        updateCheckTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: Self.updateCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForUpdates()
            }
        }
        timer.tolerance = 60
        updateCheckTimer = timer
    }

    private func startRunLogRefreshTimer() {
        runLogRefreshTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: Self.runLogRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshLatestRecords()
            }
        }
        timer.tolerance = 5
        runLogRefreshTimer = timer
    }

    func reload() {
        do {
            jobs = try store.list()
            refreshLatestRecords()
        } catch { lastMessage = error.localizedDescription }
    }

    func refreshLatestRecords() {
        latestRecords = Dictionary(uniqueKeysWithValues: jobs.compactMap { job in
            guard let record = try? logStore.records(for: job.id).first else { return nil }
            return (job.id, record)
        })
    }

    func checkForUpdates() {
        guard !updateState.isBusy else { return }
        updateState = .checking
        let updater = releaseUpdater
        let localVersion = appVersion.semanticVersion
        Task {
            do {
                let release = try await updater.fetchLatestRelease()
                let availability = updater.availability(localVersion: localVersion, release: release)
                await MainActor.run {
                    switch availability {
                    case .upToDate(_, let remote):
                        self.updateState = .upToDate(remote.tagDescription)
                    case .updateAvailable(let release, let asset):
                        self.updateState = .available(release: release, asset: asset)
                    case .noCompatibleAsset(let release):
                        self.updateState = .noCompatibleAsset(release.tagName)
                    case .localDevelopmentBuild(let release):
                        self.updateState = .developmentBuild(release.tagName)
                    case .invalidRemoteVersion(let tag):
                        self.updateState = .failed(String(format: self.localizer.text("update.invalidVersion"), tag))
                    }
                    self.lastUpdateCheckedAt = Date()
                }
            } catch {
                await MainActor.run {
                    self.updateState = .failed(error.localizedDescription)
                    self.lastUpdateCheckedAt = Date()
                }
            }
        }
    }

    func installAvailableUpdate() {
        guard case .available(let release, let asset) = updateState else { return }
        let checksumAsset = releaseUpdater.checksumAsset(for: asset, in: release)
        updateState = .installing(release.tagName)
        lastMessage = String(format: localizer.text("update.installing"), release.tagName)
        Task {
            do {
                try await updateInstaller.downloadVerifyAndPrepareRelaunch(
                    release: release,
                    asset: asset,
                    checksumAsset: checksumAsset
                )
                await MainActor.run {
                    self.updateState = .restarting
                    self.lastMessage = self.localizer.text("update.restartSoon")
                    NSApplication.shared.terminate(nil)
                }
            } catch {
                await MainActor.run {
                    self.updateState = .failed(error.localizedDescription)
                    self.lastMessage = String(format: self.localizer.text("update.failed"), error.localizedDescription)
                }
            }
        }
    }

    func updateStatusText(localizer: Localizer) -> String {
        switch updateState {
        case .idle:
            localizer.text("update.idle")
        case .checking:
            localizer.text("update.checking")
        case .upToDate:
            localizer.text("update.upToDate")
        case .available(let release, _):
            String(format: localizer.text("update.available"), release.tagName)
        case .noCompatibleAsset(let tag):
            String(format: localizer.text("update.noCompatibleAsset"), tag)
        case .developmentBuild(let tag):
            String(format: localizer.text("update.developmentBuild"), tag)
        case .installing(let tag):
            String(format: localizer.text("update.installing"), tag)
        case .restarting:
            localizer.text("update.restartSoon")
        case .failed(let message):
            String(format: localizer.text("update.failed"), message)
        }
    }

    func add(_ job: ScriptJob) {
        guard !job.requiresAdministratorPrivileges else {
            authorizeThenSave(job, isUpdate: false)
            return
        }
        saveNewJob(job)
    }

    private func saveNewJob(_ job: ScriptJob) {
        do {
            try job.schedule.validate()
            try store.add(job)
            try syncScheduler()
            lastMessage = String(format: localizer.text("job.added"), job.name)
            reload()
        } catch { lastMessage = error.localizedDescription }
    }

    func update(_ job: ScriptJob) {
        guard !job.requiresAdministratorPrivileges else {
            authorizeThenSave(job, isUpdate: true)
            return
        }
        saveExistingJob(job)
    }

    private func saveExistingJob(_ job: ScriptJob) {
        do {
            try job.schedule.validate()
            try store.update(job)
            try syncScheduler()
            lastMessage = String(format: localizer.text("job.updated"), job.name)
            reload()
        } catch { lastMessage = error.localizedDescription }
    }

    private func authorizeThenSave(_ job: ScriptJob, isUpdate: Bool) {
        lastMessage = localizer.text("sudo.authorizing")
        Task.detached(priority: .userInitiated) { [sudoSession, job] in
            do {
                try await sudoSession.ensureAuthorized()
                await MainActor.run {
                    if isUpdate {
                        self.saveExistingJob(job)
                    } else {
                        self.saveNewJob(job)
                    }
                }
            } catch {
                await MainActor.run { self.lastMessage = error.localizedDescription }
            }
        }
    }

    private func authorizeSavedPrivilegedJobsIfNeeded() {
        guard jobs.contains(where: { $0.enabled && $0.requiresAdministratorPrivileges }) else { return }
        lastMessage = localizer.text("sudo.authorizing")
        Task.detached(priority: .userInitiated) { [sudoSession] in
            do {
                try await sudoSession.ensureAuthorized()
                await MainActor.run { self.lastMessage = self.localizer.text("sudo.ready") }
            } catch {
                await MainActor.run { self.lastMessage = error.localizedDescription }
            }
        }
    }

    func delete(_ job: ScriptJob) {
        do {
            let removed = try store.remove(nameOrID: job.id.uuidString)
            try syncScheduler()
            lastMessage = String(format: localizer.text("job.removed"), removed.name)
            reload()
        } catch { lastMessage = error.localizedDescription }
    }

    func run(_ job: ScriptJob) {
        guard !runningJobIDs.contains(job.id) else { return }
        let inputSelection: ScriptRunInputSelection?
        do {
            inputSelection = try promptInputSelectionIfNeeded(for: job)
        } catch {
            lastMessage = error.localizedDescription
            return
        }
        runningJobIDs.insert(job.id)
        lastMessage = "\(localizer.text("common.run")): \(job.name)"
        Task.detached(priority: .userInitiated) { [runner, sudoSession, job, inputSelection] in
            do {
                let record = if job.requiresAdministratorPrivileges {
                    try await sudoSession.run(job, logStore: runner.logStore, timeout: runner.timeout, inputSelection: inputSelection)
                } else {
                    try runner.run(job, inputSelection: inputSelection)
                }
                await MainActor.run {
                    self.latestRecords[job.id] = record
                    self.runningJobIDs.remove(job.id)
                    self.lastMessage = String(format: self.localizer.text("run.jobExit"), job.name, record.exitCode)
                    self.notificationService.notifyRunFinished(record: record, localizer: self.localizer)
                }
            } catch {
                await MainActor.run {
                    self.runningJobIDs.remove(job.id)
                    self.lastMessage = error.localizedDescription
                    self.notificationService.notifyRunStartFailed(job: job, error: error, localizer: self.localizer)
                }
            }
        }
    }

    private func promptInputSelectionIfNeeded(for job: ScriptJob) throws -> ScriptRunInputSelection? {
        let choices = job.inputPolicy.answerChoices
        guard choices.count > 1 else { return nil }

        let alert = NSAlert()
        alert.messageText = localizer.text("run.chooseAnswerTitle")
        alert.informativeText = String(format: localizer.text("run.chooseAnswerMessage"), job.name)
        for choice in choices {
            alert.addButton(withTitle: choice.label)
        }
        alert.addButton(withTitle: localizer.text("common.cancel"))
        let response = alert.runModal()
        let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        guard choices.indices.contains(index) else {
            throw ScriptInputResolutionError.requiredAnswerMissing
        }
        return ScriptRunInputSelection(choiceID: choices[index].id)
    }

    func isRunning(_ job: ScriptJob) -> Bool {
        runningJobIDs.contains(job.id)
    }

    func toggle(_ job: ScriptJob) {
        do {
            _ = try store.setEnabled(nameOrID: job.id.uuidString, enabled: !job.enabled)
            try syncScheduler()
            reload()
        } catch { lastMessage = error.localizedDescription }
    }

    func latestRecord(for job: ScriptJob) -> RunRecord? { latestRecords[job.id] }

    func runRecords(for job: ScriptJob) -> [RunRecord] {
        do {
            let active = try logStore.records(for: job.id)
            let stashed = try logStore.stashedRecords(for: job.id)
            return (active + stashed).sorted { $0.startedAt > $1.startedAt }
        } catch {
            lastMessage = error.localizedDescription
            return []
        }
    }

    func saveSettings() {
        do {
            try settingsStore.save(settings)
            applyBackgroundMode()
        }
        catch { lastMessage = error.localizedDescription }
    }

    func stashOldLogs() {
        performLogMaintenance(showMessage: true)
        reload()
    }

    private func performLogMaintenance(showMessage: Bool) {
        do {
            let summary = try logStore.stashLogs(olderThanDays: settings.logRetentionDays)
            if showMessage || summary.stashedRuns > 0 {
                lastMessage = String(format: localizer.text("logs.stashedSummary"), summary.stashedRuns)
            }
        } catch {
            if showMessage { lastMessage = error.localizedDescription }
        }
    }

    private func applyBackgroundMode() {
        NSApplication.shared.setActivationPolicy(settings.runsInBackground ? .accessory : .regular)
    }

    private func syncScheduler() throws {
        _ = try scheduler.sync(jobs: store.list(), dryRun: false)
    }
}
