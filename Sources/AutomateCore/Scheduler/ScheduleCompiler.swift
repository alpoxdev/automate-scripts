import Foundation

public struct LaunchAgentSpec: Codable, Equatable, Sendable {
    public var label: String
    public var programArguments: [String]
    public var workingDirectory: String?
    public var environment: [String: String]
    public var runAtLoad: Bool
    public var startInterval: Int?
    public var startCalendarInterval: [[String: Int]]?
    public var standardOutPath: String?
    public var standardErrorPath: String?

    public init(label: String, programArguments: [String], workingDirectory: String? = nil, environment: [String: String] = [:], runAtLoad: Bool = false, startInterval: Int? = nil, startCalendarInterval: [[String : Int]]? = nil, standardOutPath: String? = nil, standardErrorPath: String? = nil) {
        self.label = label
        self.programArguments = programArguments
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.runAtLoad = runAtLoad
        self.startInterval = startInterval
        self.startCalendarInterval = startCalendarInterval
        self.standardOutPath = standardOutPath
        self.standardErrorPath = standardErrorPath
    }
}

public enum ScheduleCompiler {
    public static let labelPrefix = "com.alpox.automate-scripts.job"

    public static func label(for job: ScriptJob) -> String {
        let safeName = job.name.lowercased().map { char -> Character in
            char.isLetter || char.isNumber ? char : "-"
        }.reduce("") { $0 + String($1) }
        return "\(labelPrefix).\(safeName).\(job.id.uuidString.lowercased())"
    }

    public static func compile(
        job: ScriptJob,
        runnerPath: String = "/usr/local/bin/automate",
        storePath: String = JobStore.defaultFileURL().path,
        logDirectory: String? = nil
    ) throws -> LaunchAgentSpec? {
        guard job.enabled else { return nil }
        try job.schedule.validate()
        guard job.schedule != .manualOnly else { return nil }
        let invocation = CommandLineParser.normalized(commandText: job.command, arguments: job.arguments)
        let prepared = try CommandPreparation.prepare(invocation: invocation, job: job, context: .scheduled)
        let environment = CommandExecutionEnvironment.augmentedEnvironment(
            for: prepared.invocation,
            base: prepared.environment
        )
        var spec = LaunchAgentSpec(
            label: label(for: job),
            programArguments: scheduledProgramArguments(job: job, runnerPath: runnerPath, storePath: storePath),
            workingDirectory: job.workingDirectory ?? AppPaths.defaultWorkingDirectory().path,
            environment: environment,
            standardOutPath: logDirectory.map { "\($0)/\(job.id.uuidString)-stdout.log" },
            standardErrorPath: logDirectory.map { "\($0)/\(job.id.uuidString)-stderr.log" }
        )
        switch job.schedule {
        case .manualOnly:
            return nil
        case .atLogin:
            spec.runAtLoad = true
        case .everyMinutes(let minutes):
            spec.startCalendarInterval = calendarIntervals(everyMinutes: minutes)
        case .hourly(let minute):
            spec.startCalendarInterval = [["Minute": minute]]
        case .daily(let hour, let minute):
            spec.startCalendarInterval = [["Hour": hour, "Minute": minute]]
        case .weekly(let weekday, let hour, let minute):
            spec.startCalendarInterval = [["Weekday": weekday.rawValue, "Hour": hour, "Minute": minute]]
        case .monthly(let day, let hour, let minute):
            spec.startCalendarInterval = [["Day": day, "Hour": hour, "Minute": minute]]
        }
        return spec
    }

    private static func calendarIntervals(everyMinutes minutes: Int) -> [[String: Int]] {
        stride(from: 0, to: 60, by: minutes).map { ["Minute": $0] }
    }

    private static func scheduledProgramArguments(job: ScriptJob, runnerPath: String, storePath: String) -> [String] {
        [runnerPath, "--store", storePath, "run", job.id.uuidString]
    }

    public static func propertyListDictionary(for spec: LaunchAgentSpec) -> [String: Any] {
        var dict: [String: Any] = [
            "Label": spec.label,
            "ProgramArguments": spec.programArguments,
            "RunAtLoad": spec.runAtLoad
        ]
        if let workingDirectory = spec.workingDirectory { dict["WorkingDirectory"] = workingDirectory }
        if !spec.environment.isEmpty { dict["EnvironmentVariables"] = spec.environment }
        if let startInterval = spec.startInterval { dict["StartInterval"] = startInterval }
        if let startCalendarInterval = spec.startCalendarInterval { dict["StartCalendarInterval"] = startCalendarInterval.count == 1 ? startCalendarInterval[0] : startCalendarInterval }
        if let standardOutPath = spec.standardOutPath { dict["StandardOutPath"] = standardOutPath }
        if let standardErrorPath = spec.standardErrorPath { dict["StandardErrorPath"] = standardErrorPath }
        return dict
    }
}
