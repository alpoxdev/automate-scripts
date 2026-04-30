import Foundation

public enum ReleaseArchitecture: String, Sendable {
    case arm64
    case x86_64

    public var assetSuffix: String {
        switch self {
        case .arm64: "arm64"
        case .x86_64: "x86_64"
        }
    }

    public static var current: ReleaseArchitecture {
        #if arch(arm64)
        .arm64
        #else
        .x86_64
        #endif
    }
}

public struct GitHubReleaseAsset: Codable, Equatable, Sendable {
    public let name: String
    public let browserDownloadURL: URL
    public let size: Int?
    public let digest: String?

    public init(name: String, browserDownloadURL: URL, size: Int? = nil, digest: String? = nil) {
        self.name = name
        self.browserDownloadURL = browserDownloadURL
        self.size = size
        self.digest = digest
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
        case digest
    }
}

public struct GitHubRelease: Codable, Equatable, Sendable {
    public let tagName: String
    public let name: String?
    public let htmlURL: URL
    public let publishedAt: Date?
    public let assets: [GitHubReleaseAsset]

    public var semanticVersion: SemanticVersion? { SemanticVersion(tagName) }

    public init(tagName: String, name: String? = nil, htmlURL: URL, publishedAt: Date? = nil, assets: [GitHubReleaseAsset]) {
        self.tagName = tagName
        self.name = name
        self.htmlURL = htmlURL
        self.publishedAt = publishedAt
        self.assets = assets
    }

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case assets
    }
}

public enum UpdateAvailability: Equatable, Sendable {
    case upToDate(local: SemanticVersion, remote: SemanticVersion)
    case updateAvailable(release: GitHubRelease, asset: GitHubReleaseAsset)
    case noCompatibleAsset(release: GitHubRelease)
    case localDevelopmentBuild(release: GitHubRelease)
    case invalidRemoteVersion(tag: String)
}

public struct GitHubReleaseUpdater: Sendable {
    public let owner: String
    public let repository: String

    public init(owner: String = "alpoxdev", repository: String = "automate-scripts") {
        self.owner = owner
        self.repository = repository
    }

    public var latestReleaseURL: URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/latest")!
    }

    public func makeLatestReleaseRequest() -> URLRequest {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("AutomateScripts", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }

    public func fetchLatestRelease() async throws -> GitHubRelease {
        let request = makeLatestReleaseRequest()
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw GitHubReleaseUpdaterError.badResponse
        }
        return try Self.decodeRelease(from: data)
    }

    public static func decodeRelease(from data: Data) throws -> GitHubRelease {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GitHubRelease.self, from: data)
    }

    public func availability(
        localVersion: SemanticVersion?,
        release: GitHubRelease,
        architecture: ReleaseArchitecture = .current
    ) -> UpdateAvailability {
        guard let remoteVersion = release.semanticVersion else {
            return .invalidRemoteVersion(tag: release.tagName)
        }
        guard let localVersion else {
            return .localDevelopmentBuild(release: release)
        }
        guard remoteVersion > localVersion else {
            return .upToDate(local: localVersion, remote: remoteVersion)
        }
        guard let asset = compatibleDMGAsset(in: release, architecture: architecture) else {
            return .noCompatibleAsset(release: release)
        }
        return .updateAvailable(release: release, asset: asset)
    }

    public func compatibleDMGAsset(in release: GitHubRelease, architecture: ReleaseArchitecture) -> GitHubReleaseAsset? {
        let expectedName = "AutomateScripts-\(release.tagName)-macos-\(architecture.assetSuffix).dmg"
        return release.assets.first(where: { $0.name == expectedName })
    }

    public func checksumAsset(for asset: GitHubReleaseAsset, in release: GitHubRelease) -> GitHubReleaseAsset? {
        release.assets.first {
            $0.name == "\(asset.name).sha256"
                || $0.name == asset.name.replacingSuffix(".dmg", with: ".sha256")
        }
    }

    public static func isTrustedDownloadURL(_ url: URL) -> Bool {
        guard url.scheme == "https" else { return false }
        let host = url.host?.lowercased() ?? ""
        return host == "github.com"
            || host.hasSuffix(".github.com")
            || host == "githubusercontent.com"
            || host.hasSuffix(".githubusercontent.com")
    }
}

public enum GitHubReleaseUpdaterError: Error, LocalizedError, Sendable {
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .badResponse: "GitHub release request failed."
        }
    }
}

private extension String {
    func replacingSuffix(_ suffix: String, with replacement: String) -> String {
        guard hasSuffix(suffix) else { return self }
        return String(dropLast(suffix.count)) + replacement
    }
}
