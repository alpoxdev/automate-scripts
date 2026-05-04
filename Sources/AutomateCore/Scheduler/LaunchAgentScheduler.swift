import Darwin
import Foundation

public protocol LaunchAgentControlling: Sendable {
    func bootstrap(plistURL: URL) throws
    func bootout(label: String) throws
}

public struct LaunchctlController: LaunchAgentControlling {
    public init() {}

    public func bootstrap(plistURL: URL) throws {
        try runLaunchctl(arguments: ["bootstrap", userDomainTarget(), plistURL.path])
    }

    public func bootout(label: String) throws {
        try runLaunchctl(arguments: ["bootout", "\(userDomainTarget())/\(label)"])
    }

    private func userDomainTarget() -> String {
        "gui/\(getuid())"
    }

    private func runLaunchctl(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw LaunchAgentSchedulerError.launchctlFailed(arguments: arguments, status: process.terminationStatus, message: message ?? "")
        }
    }
}

public enum LaunchAgentSchedulerError: Error, LocalizedError, Sendable {
    case launchctlFailed(arguments: [String], status: Int32, message: String)

    public var errorDescription: String? {
        switch self {
        case .launchctlFailed(let arguments, let status, let message):
            let suffix = message.isEmpty ? "" : ": \(message)"
            return "launchctl \(arguments.joined(separator: " ")) failed with status \(status)\(suffix)"
        }
    }
}

public final class LaunchAgentScheduler: SchedulerBackend, @unchecked Sendable {
    public let launchAgentsDirectory: URL
    public let runnerPath: String
    public let storeURL: URL
    public let logDirectory: URL
    public let reloadServices: Bool
    private let launchController: any LaunchAgentControlling

    public init(
        launchAgentsDirectory: URL = LaunchAgentScheduler.defaultLaunchAgentsDirectory(),
        runnerPath: String = LaunchAgentScheduler.defaultRunnerPath(),
        storeURL: URL = JobStore.defaultFileURL(),
        logDirectory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("AutomateScripts/Logs", isDirectory: true),
        reloadServices: Bool? = nil,
        launchController: any LaunchAgentControlling = LaunchctlController()
    ) {
        self.launchAgentsDirectory = launchAgentsDirectory
        self.runnerPath = runnerPath
        self.storeURL = storeURL
        self.logDirectory = logDirectory
        self.reloadServices = reloadServices ?? Self.isDefaultLaunchAgentsDirectory(launchAgentsDirectory)
        self.launchController = launchController
    }

    public static func defaultLaunchAgentsDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }

    public static func defaultRunnerPath(bundle: Bundle = .main, arguments: [String] = CommandLine.arguments) -> String {
        if bundle.bundleURL.pathExtension == "app" {
            let bundledRunner = bundle.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("MacOS", isDirectory: true)
                .appendingPathComponent("automate")
            if FileManager.default.fileExists(atPath: bundledRunner.path) {
                return bundledRunner.path
            }
        }

        if let executable = arguments.first {
            let executableURL = URL(fileURLWithPath: executable)
            if executableURL.lastPathComponent == "automate" {
                return executableURL.path
            }
        }

        return "/usr/local/bin/automate"
    }

    private static func isDefaultLaunchAgentsDirectory(_ url: URL) -> Bool {
        url.standardizedFileURL.path == defaultLaunchAgentsDirectory().standardizedFileURL.path
    }

    public func sync(jobs: [ScriptJob], dryRun: Bool = false) throws -> SchedulerSyncPlan {
        if !dryRun {
            try FileManager.default.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        }
        let desiredSpecs = try jobs.compactMap {
            try ScheduleCompiler.compile(
                job: $0,
                runnerPath: runnerPath,
                storePath: storeURL.path,
                logDirectory: logDirectory.path
            )
        }
        let desiredLabels = Set(desiredSpecs.map(\.label))
        let existing = try managedPlistURLs()
        var plan = SchedulerSyncPlan(dryRun: dryRun)

        for spec in desiredSpecs {
            let url = plistURL(label: spec.label)
            let desiredData = try Self.serializedPlistData(for: spec)
            let existingData = (try? Data(contentsOf: url))
            if existingData == desiredData {
                plan.unchanged.append(spec.label)
                continue
            }
            plan.createdOrUpdated.append(spec.label)
            if !dryRun {
                try write(data: desiredData, to: url)
                if reloadServices {
                    try? launchController.bootout(label: spec.label)
                    try launchController.bootstrap(plistURL: url)
                }
            }
        }

        for url in existing {
            let label = url.deletingPathExtension().lastPathComponent
            if !desiredLabels.contains(label) {
                plan.removed.append(label)
                if !dryRun {
                    if reloadServices { try? launchController.bootout(label: label) }
                    try FileManager.default.removeItem(at: url)
                }
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
        try write(data: Self.serializedPlistData(for: spec), to: url)
    }

    private func write(data: Data, to url: URL) throws {
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).tmp")
        try data.write(to: tmp, options: [.atomic])
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try FileManager.default.moveItem(at: tmp, to: url)
    }

    private static func serializedPlistData(for spec: LaunchAgentSpec) throws -> Data {
        let dict = ScheduleCompiler.propertyListDictionary(for: spec)
        return try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    private func managedPlistURLs() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: launchAgentsDirectory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: launchAgentsDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "plist" && $0.deletingPathExtension().lastPathComponent.hasPrefix(ScheduleCompiler.labelPrefix) }
    }

    private func plistURL(label: String) -> URL { launchAgentsDirectory.appendingPathComponent("\(label).plist") }
}
