import AutomateCore
import Foundation
import XCTest

final class SemanticVersionTests: XCTestCase {
    func testSemanticVersionParsesTagsAndComparesNumerically() throws {
        XCTAssertEqual(SemanticVersion("v1.2.3"), SemanticVersion(major: 1, minor: 2, patch: 3))
        XCTAssertEqual(SemanticVersion("1.2.3"), SemanticVersion(major: 1, minor: 2, patch: 3))
        XCTAssertGreaterThan(try XCTUnwrap(SemanticVersion("v1.2.10")), try XCTUnwrap(SemanticVersion("v1.2.9")))
        XCTAssertGreaterThan(try XCTUnwrap(SemanticVersion("v2.0.0")), try XCTUnwrap(SemanticVersion("v1.99.99")))
        XCTAssertNil(SemanticVersion("release-1.2.3"))
        XCTAssertNil(SemanticVersion("v1.2"))
    }
}

final class GitHubReleaseUpdaterTests: XCTestCase {
    func testDecodesReleaseAndSelectsArchitectureAsset() throws {
        let release = try GitHubReleaseUpdater.decodeRelease(from: Data(sampleReleaseJSON.utf8))
        XCTAssertEqual(release.tagName, "v1.2.3")
        XCTAssertEqual(release.semanticVersion, SemanticVersion(major: 1, minor: 2, patch: 3))

        let updater = GitHubReleaseUpdater(owner: "alpoxdev", repository: "automate-scripts")
        XCTAssertEqual(updater.compatibleDMGAsset(in: release, architecture: .arm64)?.name, "AutomateScripts-v1.2.3-macos-arm64.dmg")
        XCTAssertEqual(updater.compatibleDMGAsset(in: release, architecture: .x86_64)?.name, "AutomateScripts-v1.2.3-macos-x86_64.dmg")
    }

    func testAvailabilityRequiresNewerVersionAndCompatibleAsset() throws {
        let release = try GitHubReleaseUpdater.decodeRelease(from: Data(sampleReleaseJSON.utf8))
        let updater = GitHubReleaseUpdater()

        let available = updater.availability(localVersion: SemanticVersion("v1.2.2"), release: release, architecture: .arm64)
        guard case .updateAvailable(_, let asset) = available else {
            return XCTFail("Expected updateAvailable, got \(available)")
        }
        XCTAssertEqual(asset.name, "AutomateScripts-v1.2.3-macos-arm64.dmg")

        XCTAssertEqual(
            updater.availability(localVersion: SemanticVersion("v1.2.3"), release: release, architecture: .arm64),
            .upToDate(local: SemanticVersion(major: 1, minor: 2, patch: 3), remote: SemanticVersion(major: 1, minor: 2, patch: 3))
        )

        guard case .localDevelopmentBuild = updater.availability(localVersion: nil, release: release, architecture: .arm64) else {
            return XCTFail("Expected development build handling")
        }
    }

    func testNoCompatibleAssetAndInvalidRemoteVersionAreNotInstallable() throws {
        let release = GitHubRelease(
            tagName: "v2.0.0",
            htmlURL: URL(string: "https://github.com/alpoxdev/automate-scripts/releases/tag/v2.0.0")!,
            assets: [
                GitHubReleaseAsset(
                    name: "AutomateScripts-v1.9.9-macos-arm64.dmg",
                    browserDownloadURL: URL(string: "https://github.com/alpoxdev/automate-scripts/releases/download/v2.0.0/AutomateScripts-v1.9.9-macos-arm64.dmg")!
                )
            ]
        )
        let updater = GitHubReleaseUpdater()
        XCTAssertEqual(
            updater.availability(localVersion: SemanticVersion("v1.0.0"), release: release, architecture: .arm64),
            .noCompatibleAsset(release: release)
        )

        let invalidRelease = GitHubRelease(
            tagName: "latest",
            htmlURL: URL(string: "https://github.com/alpoxdev/automate-scripts/releases/tag/latest")!,
            assets: []
        )
        XCTAssertEqual(
            updater.availability(localVersion: SemanticVersion("v1.0.0"), release: invalidRelease, architecture: .arm64),
            .invalidRemoteVersion(tag: "latest")
        )
    }

    func testTrustedDownloadURLRequiresHTTPSAndHostBoundary() {
        XCTAssertTrue(GitHubReleaseUpdater.isTrustedDownloadURL(URL(string: "https://github.com/alpoxdev/automate-scripts/releases/download/v1.0.0/app.dmg")!))
        XCTAssertTrue(GitHubReleaseUpdater.isTrustedDownloadURL(URL(string: "https://objects.githubusercontent.com/github-production-release-asset/app.dmg")!))
        XCTAssertFalse(GitHubReleaseUpdater.isTrustedDownloadURL(URL(string: "http://github.com/alpoxdev/automate-scripts/releases/download/v1.0.0/app.dmg")!))
        XCTAssertFalse(GitHubReleaseUpdater.isTrustedDownloadURL(URL(string: "https://evilgithubusercontent.com/app.dmg")!))
        XCTAssertFalse(GitHubReleaseUpdater.isTrustedDownloadURL(URL(string: "https://github.com.evil.example/app.dmg")!))
    }

    func testChecksumParsesGitHubDigestAndSidecar() throws {
        let data = Data("hello".utf8)
        let expected = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        let digestChecksum = try XCTUnwrap(UpdateChecksum(digest: "sha256:\(expected)"))
        XCTAssertTrue(digestChecksum.verify(data: data))
        XCTAssertFalse(digestChecksum.verify(data: Data("goodbye".utf8)))

        let sidecarChecksum = try XCTUnwrap(UpdateChecksum(sidecarContents: "\(expected)  AutomateScripts-v1.2.3-macos-arm64.dmg\n"))
        XCTAssertEqual(sidecarChecksum, digestChecksum)
    }
}

private let sampleReleaseJSON = #"""
{
  "tag_name": "v1.2.3",
  "name": "Automate Scripts v1.2.3",
  "html_url": "https://github.com/alpoxdev/automate-scripts/releases/tag/v1.2.3",
  "published_at": "2026-04-30T00:00:00Z",
  "assets": [
    {
      "name": "AutomateScripts-v1.2.3-macos-arm64.dmg",
      "browser_download_url": "https://github.com/alpoxdev/automate-scripts/releases/download/v1.2.3/AutomateScripts-v1.2.3-macos-arm64.dmg",
      "size": 123,
      "digest": "sha256:2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
    },
    {
      "name": "AutomateScripts-v1.2.3-macos-x86_64.dmg",
      "browser_download_url": "https://github.com/alpoxdev/automate-scripts/releases/download/v1.2.3/AutomateScripts-v1.2.3-macos-x86_64.dmg",
      "size": 456
    },
    {
      "name": "AutomateScripts-v1.2.3-macos-x86_64.dmg.sha256",
      "browser_download_url": "https://github.com/alpoxdev/automate-scripts/releases/download/v1.2.3/AutomateScripts-v1.2.3-macos-x86_64.dmg.sha256"
    }
  ]
}
"""#
