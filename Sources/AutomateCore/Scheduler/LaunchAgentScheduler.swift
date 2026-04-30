import Foundation

public final class LaunchAgentScheduler: SchedulerBackend, @unchecked Sendable {
    public let launchAgentsDirectory: URL
    public let runnerPath: String
    public let logDirectory: URL

    public init(
        launchAgentsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents", isDirectory: true),
        runnerPath: String = "/usr/bin/env",
        logDirectory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("AutomateScripts/Logs", isDirectory: true)
    ) {
        self.launchAgentsDirectory = launchAgentsDirectory
        self.runnerPath = runnerPath
        self.logDirectory = logDirectory
    }

    public func sync(jobs: [ScriptJob], dryRun: Bool = false) throws -> SchedulerSyncPlan {
        if !dryRun {
            try FileManager.default.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        }
        let desiredSpecs = try jobs.compactMap { try ScheduleCompiler.compile(job: $0, runnerPath: runnerPath, logDirectory: logDirectory.path) }
        let desiredLabels = Set(desiredSpecs.map(\.label))
        let existing = try managedPlistURLs()
        var plan = SchedulerSyncPlan(dryRun: dryRun)

        for spec in desiredSpecs {
            let url = plistURL(label: spec.label)
            plan.createdOrUpdated.append(spec.label)
            if !dryRun { try write(spec: spec, to: url) }
        }

        for url in existing {
            let label = url.deletingPathExtension().lastPathComponent
            if !desiredLabels.contains(label) {
                plan.removed.append(label)
                if !dryRun { try FileManager.default.removeItem(at: url) }
            }
        }

        let scheduledIDs = Set(desiredSpecs.map(\.label))
        for job in jobs where !job.enabled || job.schedule == .manualOnly {
            let label = ScheduleCompiler.label(for: job)
            if !scheduledIDs.contains(label) { plan.skipped.append(job.name) }
        }
        return plan
    }

    public func write(spec: LaunchAgentSpec, to url: URL) throws {
        let dict = ScheduleCompiler.propertyListDictionary(for: spec)
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).tmp")
        try data.write(to: tmp, options: [.atomic])
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try FileManager.default.moveItem(at: tmp, to: url)
    }

    private func managedPlistURLs() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: launchAgentsDirectory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: launchAgentsDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "plist" && $0.deletingPathExtension().lastPathComponent.hasPrefix(ScheduleCompiler.labelPrefix) }
    }

    private func plistURL(label: String) -> URL { launchAgentsDirectory.appendingPathComponent("\(label).plist") }
}
