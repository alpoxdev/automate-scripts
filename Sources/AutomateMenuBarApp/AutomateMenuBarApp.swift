import AutomateCore
import AppKit
import SwiftUI

@main
struct AutomateMenuBarApp: App {
    @StateObject private var model = MenuBarModel()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
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
final class MenuBarModel: ObservableObject {
    @Published var jobs: [ScriptJob] = []
    @Published var latestRecords: [UUID: RunRecord] = [:]
    @Published var runningJobIDs: Set<UUID> = []
    @Published var lastMessage: String = ""
    @Published var language: AppLanguage = .system()
    @Published var settings: AppSettings

    let store = JobStore()
    let logStore = RunLogStore()
    let settingsStore = AppSettingsStore()
    private let runner = ScriptRunner()
    private let sudoSession = SudoSession()

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
        authorizeSavedPrivilegedJobsIfNeeded()
    }

    func reload() {
        do {
            jobs = try store.list()
            latestRecords = Dictionary(uniqueKeysWithValues: jobs.compactMap { job in
                guard let record = try? logStore.records(for: job.id).first else { return nil }
                return (job.id, record)
            })
        } catch { lastMessage = error.localizedDescription }
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
                }
            } catch {
                await MainActor.run {
                    self.runningJobIDs.remove(job.id)
                    self.lastMessage = error.localizedDescription
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
}
