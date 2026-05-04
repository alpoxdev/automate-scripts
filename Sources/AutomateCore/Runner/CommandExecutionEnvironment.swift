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
                "\(homeDirectory)/.cargo/bin",
                "\(homeDirectory)/.volta/bin",
                "\(homeDirectory)/.asdf/shims",
                "\(homeDirectory)/.local/share/mise/shims"
            ])
            paths.append(contentsOf: nvmNodeBinPaths(homeDirectory: homeDirectory))
            paths.append(contentsOf: fnmNodeBinPaths(homeDirectory: homeDirectory))
        }

        paths.append(contentsOf: homebrewNodeBinPaths())
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
                isDirectory(url.appendingPathComponent("bin", isDirectory: true))
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
            .map { $0.appendingPathComponent("bin", isDirectory: true).path }
    }

    private static func fnmNodeBinPaths(homeDirectory: String) -> [String] {
        let roots = [
            URL(fileURLWithPath: homeDirectory)
                .appendingPathComponent(".fnm", isDirectory: true)
                .appendingPathComponent("node-versions", isDirectory: true),
            URL(fileURLWithPath: homeDirectory)
                .appendingPathComponent(".local/share/fnm", isDirectory: true)
                .appendingPathComponent("node-versions", isDirectory: true)
        ]
        return roots.flatMap { nodeVersionBinPaths(in: $0, binSuffix: ["installation", "bin"]) }
    }

    private static func homebrewNodeBinPaths() -> [String] {
        let optRoots = [
            URL(fileURLWithPath: "/opt/homebrew/opt", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/opt", isDirectory: true)
        ]
        var paths: [String] = []

        for optRoot in optRoots {
            guard let formulae = try? FileManager.default.contentsOfDirectory(
                at: optRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            paths.append(contentsOf: formulae
                .filter { formula in
                    formula.lastPathComponent == "node" || formula.lastPathComponent.hasPrefix("node@")
                }
                .filter { formula in
                    isDirectory(formula.appendingPathComponent("bin", isDirectory: true))
                }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
                .map { $0.appendingPathComponent("bin", isDirectory: true).path })
        }
        return paths
    }

    private static func nodeVersionBinPaths(in versionsDirectory: URL, binSuffix: [String]) -> [String] {
        guard let versions = try? FileManager.default.contentsOfDirectory(
            at: versionsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return versions
            .filter { url in
                let bin = binSuffix.reduce(url) { partial, component in
                    partial.appendingPathComponent(component, isDirectory: true)
                }
                return isDirectory(bin)
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
            .map { version in
                binSuffix.reduce(version) { url, component in
                    url.appendingPathComponent(component, isDirectory: true)
                }.path
            }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
