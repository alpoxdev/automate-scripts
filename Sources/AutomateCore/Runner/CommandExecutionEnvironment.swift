import Foundation

public enum CommandExecutionEnvironment: Sendable {
    public static func augmentedEnvironment(
        for invocation: CommandInvocation,
        base environment: [String: String],
        homeDirectory: String? = nil
    ) -> [String: String] {
        guard !invocation.command.contains("/") else { return environment }
        var result = environment
        let resolvedHome = homeDirectory ?? environment["HOME"] ?? NSHomeDirectory()
        result["PATH"] = augmentedSearchPath(existing: result["PATH"], homeDirectory: resolvedHome)
        return result
    }

    public static func augmentedSearchPath(existing: String?, homeDirectory: String? = nil) -> String {
        var seen = Set<String>()
        var paths: [String] = []

        func append(_ path: String?) {
            guard let path, !path.isEmpty, !seen.contains(path) else { return }
            seen.insert(path)
            paths.append(path)
        }

        existing?
            .split(separator: ":", omittingEmptySubsequences: true)
            .map(String.init)
            .forEach(append)

        candidateSearchPaths(homeDirectory: homeDirectory).forEach(append)
        return paths.joined(separator: ":")
    }

    private static func candidateSearchPaths(homeDirectory: String?) -> [String] {
        var paths: [String] = []

        if let homeDirectory, !homeDirectory.isEmpty {
            paths.append(contentsOf: [
                "\(homeDirectory)/.local/bin",
                "\(homeDirectory)/.npm-global/bin",
                "\(homeDirectory)/.bun/bin",
                "\(homeDirectory)/.yarn/bin",
                "\(homeDirectory)/Library/pnpm",
                "\(homeDirectory)/.cargo/bin"
            ])
            paths.append(contentsOf: nvmNodeBinPaths(homeDirectory: homeDirectory))
        }

        paths.append(contentsOf: [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ])
        return paths
    }

    private static func nvmNodeBinPaths(homeDirectory: String) -> [String] {
        let versionsDirectory = URL(fileURLWithPath: homeDirectory)
            .appendingPathComponent(".nvm", isDirectory: true)
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent("node", isDirectory: true)
        guard let versions = try? FileManager.default.contentsOfDirectory(
            at: versionsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return versions
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
            .map { $0.appendingPathComponent("bin", isDirectory: true).path }
    }
}
