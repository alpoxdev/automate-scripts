import AutomateCore
import Foundation

struct CLIError: Error, CustomStringConvertible { let description: String }

struct AutomateCLI {
    var args: [String]
    var language: AppLanguage = .system()
    var storeURL: URL?

    mutating func run() throws {
        parseGlobals()
        let localizer = Localizer(language: language)
        guard let command = args.first else { print(Self.help); return }
        args.removeFirst()
        let store = JobStore(fileURL: storeURL ?? JobStore.defaultFileURL())
        let logStore = RunLogStore(directory: (storeURL ?? JobStore.defaultFileURL()).deletingLastPathComponent().appendingPathComponent("RunLogs", isDirectory: true))
        switch command {
        case "help", "--help", "-h": print(Self.help)
        case "list": try list(store: store, localizer: localizer)
        case "add": try add(store: store, localizer: localizer)
        case "edit": try edit(store: store, localizer: localizer)
        case "remove": try remove(store: store, localizer: localizer)
        case "enable": try setEnabled(true, store: store, localizer: localizer)
        case "disable": try setEnabled(false, store: store, localizer: localizer)
        case "run": try runJob(store: store, logStore: logStore, localizer: localizer)
        case "logs": try logs(store: store, logStore: logStore, localizer: localizer)
        case "sync": try sync(store: store, localizer: localizer)
        case "doctor": print(localizer.text("doctor.ok"))
        default: throw CLIError(description: "Unknown command: \(command)\n\n\(Self.help)")
        }
    }

    mutating func parseGlobals() {
        var rest: [String] = []
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--lang" where i + 1 < args.count:
                language = AppLanguage(rawValue: args[i + 1]) ?? language; i += 2
            case "--store" where i + 1 < args.count:
                storeURL = URL(fileURLWithPath: args[i + 1]); i += 2
            default:
                rest.append(args[i]); i += 1
            }
        }
        args = rest
    }

    func list(store: JobStore, localizer: Localizer) throws {
        let jobs = try store.list()
        guard !jobs.isEmpty else { print(localizer.text("list.empty")); return }
        for job in jobs {
            let state = job.enabled ? "enabled" : "disabled"
            print("\(job.name) [\(state)] — \(localizer.scheduleDescription(job.schedule)) — \(job.command) \(job.arguments.joined(separator: " "))")
        }
    }

    mutating func add(store: JobStore, localizer: Localizer) throws {
        guard let name = popValue() else { throw CLIError(description: "Usage: automate add <name> --cmd <command> [schedule preset]") }
        let command = try option("--cmd") ?? { throw CLIError(description: "Missing --cmd") }()
        let schedule = try parseSchedulePreset()
        try schedule.validate()
        let argumentsText = try option("--args") ?? ""
        let invocation = CommandLineParser.normalized(commandText: command, argumentsText: argumentsText)
        let workingDirectory = try option("--cwd")
        let requiresAdministratorPrivileges = take("--sudo")
        let job = ScriptJob(name: name, command: invocation.command, arguments: invocation.arguments, workingDirectory: workingDirectory, requiresAdministratorPrivileges: requiresAdministratorPrivileges, schedule: schedule)
        try store.add(job)
        print(String(format: localizer.text("job.added"), name))
    }

    mutating func edit(store: JobStore, localizer: Localizer) throws {
        guard let name = popValue(), var job = try store.find(nameOrID: name) else {
            throw CLIError(description: "Usage: automate edit <name-or-id> [--name <new-name>] [--cmd <command>] [--args \"...\"] [--cwd <path>] [schedule preset]")
        }
        if let newName = try option("--name") { job.name = newName }
        let commandOption = try option("--cmd")
        let argumentsOption = try option("--args")
        if commandOption != nil || argumentsOption != nil {
            let invocation = CommandLineParser.normalized(
                commandText: commandOption ?? job.command,
                argumentsText: argumentsOption ?? job.arguments.joined(separator: " ")
            )
            job.command = invocation.command
            job.arguments = invocation.arguments
        }
        if let workingDirectory = try option("--cwd") { job.workingDirectory = workingDirectory }
        if take("--sudo") { job.requiresAdministratorPrivileges = true }
        if take("--no-sudo") { job.requiresAdministratorPrivileges = false }
        if containsScheduleFlag {
            let schedule = try parseSchedulePreset()
            try schedule.validate()
            job.schedule = schedule
        }
        try store.update(job)
        print(String(format: localizer.text("job.updated"), job.name))
    }

    mutating func remove(store: JobStore, localizer: Localizer) throws {
        guard let name = popValue() else { throw CLIError(description: "Usage: automate remove <name>") }
        let removed = try store.remove(nameOrID: name)
        print(String(format: localizer.text("job.removed"), removed.name))
    }

    mutating func setEnabled(_ enabled: Bool, store: JobStore, localizer: Localizer) throws {
        guard let name = popValue() else { throw CLIError(description: "Usage: automate \(enabled ? "enable" : "disable") <name>") }
        let job = try store.setEnabled(nameOrID: name, enabled: enabled)
        print(String(format: localizer.text(enabled ? "job.enabled" : "job.disabled"), job.name))
    }

    mutating func runJob(store: JobStore, logStore: RunLogStore, localizer: Localizer) throws {
        guard let name = popValue(), let job = try store.find(nameOrID: name) else { throw CLIError(description: "Usage: automate run <name>") }
        let record = try ScriptRunner(logStore: logStore).run(job)
        print(String(format: localizer.text("run.completed"), record.exitCode))
        if let path = record.stdoutPath { print("stdout: \(path)") }
        if let path = record.stderrPath { print("stderr: \(path)") }
    }

    mutating func logs(store: JobStore, logStore: RunLogStore, localizer: Localizer) throws {
        guard let name = popValue(), let job = try store.find(nameOrID: name) else { throw CLIError(description: "Usage: automate logs <name>") }
        for record in try logStore.records(for: job.id) {
            print("\(record.startedAt) exit=\(record.exitCode) stdout=\(record.stdoutPath ?? "-") stderr=\(record.stderrPath ?? "-")")
        }
    }

    mutating func sync(store: JobStore, localizer: Localizer) throws {
        let dryRun = args.contains("--dry-run") || !args.contains("--apply")
        let scheduler = LaunchAgentScheduler(launchAgentsDirectory: (storeURL ?? JobStore.defaultFileURL()).deletingLastPathComponent().appendingPathComponent("LaunchAgents", isDirectory: true))
        let plan = try scheduler.sync(jobs: store.list(), dryRun: dryRun)
        print(String(format: localizer.text("sync.dryRun"), plan.summary))
    }

    mutating func parseSchedulePreset() throws -> SchedulePreset {
        if args.contains("--cron") { throw CLIError(description: Localizer(language: language).text("error.rawCronUnsupported")) }
        if take("--manual") { return .manualOnly }
        if take("--at-login") { return .atLogin }
        if let value = try option("--every-minutes") { let minutes = try int(value, "minutes"); return .everyMinutes(minutes) }
        if let value = try option("--hourly") { return .hourly(minute: try int(value, "minute")) }
        if let value = try option("--daily") { let t = try parseTime(value); return .daily(hour: t.hour, minute: t.minute) }
        if let index = args.firstIndex(of: "--weekly"), index + 2 < args.count {
            let weekdayToken = args[index + 1]
            let timeToken = args[index + 2]
            args.removeSubrange(index...(index + 2))
            guard let weekday = Weekday(token: weekdayToken) else { throw CLIError(description: "Invalid weekday: \(weekdayToken)") }
            let t = try parseTime(timeToken)
            return .weekly(weekday: weekday, hour: t.hour, minute: t.minute)
        }
        if let index = args.firstIndex(of: "--monthly"), index + 2 < args.count {
            let day = try int(args[index + 1], "day")
            let t = try parseTime(args[index + 2])
            args.removeSubrange(index...(index + 2))
            return .monthly(day: day, hour: t.hour, minute: t.minute)
        }
        return .manualOnly
    }

    var containsScheduleFlag: Bool {
        let flags = ["--manual", "--at-login", "--every-minutes", "--hourly", "--daily", "--weekly", "--monthly", "--cron"]
        return args.contains { flags.contains($0) }
    }

    mutating func take(_ flag: String) -> Bool {
        guard let i = args.firstIndex(of: flag) else { return false }
        args.remove(at: i)
        return true
    }

    mutating func option(_ flag: String) throws -> String? {
        guard let i = args.firstIndex(of: flag) else { return nil }
        guard i + 1 < args.count else { throw CLIError(description: "Missing value for \(flag)") }
        let value = args[i + 1]
        args.removeSubrange(i...(i + 1))
        return value
    }

    mutating func popValue() -> String? { args.isEmpty ? nil : args.removeFirst() }

    func parseTime(_ value: String) throws -> (hour: Int, minute: Int) {
        let parts = value.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { throw CLIError(description: "Invalid time: \(value). Use HH:mm") }
        return (hour, minute)
    }

    func int(_ value: String, _ name: String) throws -> Int {
        guard let result = Int(value) else { throw CLIError(description: "Invalid \(name): \(value)") }
        return result
    }

    static let help = """
    automate — friendly macOS script automation manager

    Global: --store <path> --lang en|ko
    Commands:
      list
      add <name> --cmd <command> [--args "..."] [--cwd <path>] [--sudo] [--manual|--at-login|--every-minutes 5|10|15|30|--hourly <minute>|--daily HH:mm|--weekly mon HH:mm|--monthly <day> HH:mm]
      edit <name-or-id> [--name <new-name>] [--cmd <command>] [--args "..."] [--cwd <path>] [--sudo|--no-sudo] [schedule preset]
      remove <name>
      enable <name>
      disable <name>
      run <name>
      logs <name>
      sync [--dry-run|--apply]
      doctor
    Raw cron expressions are intentionally not accepted in the default UX.
    """
}

var cli = AutomateCLI(args: Array(CommandLine.arguments.dropFirst()))
do {
    try cli.run()
} catch {
    let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
    fputs("\(message)\n", stderr)
    exit(1)
}
