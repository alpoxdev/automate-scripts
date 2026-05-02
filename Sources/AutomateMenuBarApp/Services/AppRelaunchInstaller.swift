import AutomateCore
import AppKit
import Foundation

struct AppRelaunchInstaller {
    func downloadVerifyAndPrepareRelaunch(
        release: GitHubRelease,
        asset: GitHubReleaseAsset,
        checksumAsset: GitHubReleaseAsset?
    ) async throws {
        try validateDownloadURL(asset.browserDownloadURL)
        let data = try await downloadData(from: asset.browserDownloadURL)
        let checksum = try await checksum(for: asset, checksumAsset: checksumAsset)
        guard checksum.verify(data: data) else {
            throw AppRelaunchInstallerError.checksumMismatch
        }

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AutomateScriptsUpdate", isDirectory: true)
            .appendingPathComponent(release.tagName, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let dmgURL = tempDirectory.appendingPathComponent(asset.name)
        try data.write(to: dmgURL, options: [.atomic])

        try launchHelper(for: dmgURL, expectedVersion: release.tagName.trimmingLeadingV())
    }

    private func checksum(for asset: GitHubReleaseAsset, checksumAsset: GitHubReleaseAsset?) async throws -> UpdateChecksum {
        if let checksum = UpdateChecksum(digest: asset.digest) {
            return checksum
        }
        guard let checksumAsset else {
            throw AppRelaunchInstallerError.checksumUnavailable
        }
        try validateDownloadURL(checksumAsset.browserDownloadURL)
        let data = try await downloadData(from: checksumAsset.browserDownloadURL)
        guard let contents = String(data: data, encoding: .utf8),
              let checksum = UpdateChecksum(sidecarContents: contents) else {
            throw AppRelaunchInstallerError.checksumUnavailable
        }
        return checksum
    }

    private func validateDownloadURL(_ url: URL) throws {
        guard GitHubReleaseUpdater.isTrustedDownloadURL(url) else {
            throw AppRelaunchInstallerError.untrustedDownloadURL
        }
    }

    private func downloadData(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw AppRelaunchInstallerError.downloadFailed
        }
        return data
    }

    private func launchHelper(for dmgURL: URL, expectedVersion: String) throws {
        let appURL = Bundle.main.bundleURL
        guard appURL.pathExtension == "app" else {
            throw AppRelaunchInstallerError.notRunningFromAppBundle
        }
        let parent = appURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw AppRelaunchInstallerError.appPathNotWritable(appURL.path)
        }

        let helperURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AutomateScriptsUpdate", isDirectory: true)
            .appendingPathComponent("relaunch-\(UUID().uuidString).zsh")
        try FileManager.default.createDirectory(at: helperURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try helperScript.write(to: helperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helperURL.path)
        let logURL = try updateLogURL()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            helperURL.path,
            appURL.path,
            dmgURL.path,
            String(ProcessInfo.processInfo.processIdentifier),
            expectedVersion,
            "dev.alpox.AutomateScripts",
            "AutomateMenuBarApp",
            logURL.path
        ]
        try process.run()
    }

    private func updateLogURL() throws -> URL {
        let directory = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("AutomateScripts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("update.log")
    }

    private var helperScript: String {
        #"""
        #!/bin/zsh
        set -euo pipefail

        APP_PATH="$1"
        DMG_PATH="$2"
        APP_PID="$3"
        EXPECTED_VERSION="$4"
        EXPECTED_BUNDLE_ID="$5"
        EXPECTED_EXECUTABLE="$6"
        LOG_PATH="$7"
        mkdir -p "$(dirname "$LOG_PATH")"
        exec >> "$LOG_PATH" 2>&1
        echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Starting Automate Scripts update helper"
        echo "App path: $APP_PATH"
        echo "DMG path: $DMG_PATH"
        echo "Expected version: $EXPECTED_VERSION"

        WAIT_COUNT=0
        while kill -0 "$APP_PID" 2>/dev/null && [ "$WAIT_COUNT" -lt 75 ]; do
          sleep 0.2
          WAIT_COUNT=$((WAIT_COUNT + 1))
        done
        if kill -0 "$APP_PID" 2>/dev/null; then
          echo "App process $APP_PID did not exit after 15s; sending TERM"
          kill -TERM "$APP_PID" 2>/dev/null || true
          sleep 2
        fi
        if kill -0 "$APP_PID" 2>/dev/null; then
          echo "App process $APP_PID still alive; sending KILL"
          kill -KILL "$APP_PID" 2>/dev/null || true
          sleep 1
        fi

        MOUNT_DIR="$(mktemp -d /tmp/AutomateScriptsUpdateMount.XXXXXX)"
        UPDATE_PATH="${APP_PATH}.update"
        BACKUP_PATH="${APP_PATH}.backup-$(date +%Y%m%d%H%M%S)"

        cleanup() {
          hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true
          rm -rf "$MOUNT_DIR" "$UPDATE_PATH"
        }
        trap cleanup EXIT

        echo "Mounting update image"
        hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_DIR" -nobrowse -quiet
        SOURCE_APP="$(find "$MOUNT_DIR" -maxdepth 2 -name 'Automate Scripts.app' -type d | head -n 1)"
        if [ -z "$SOURCE_APP" ]; then
          echo "Automate Scripts.app not found in update image" >&2
          exit 1
        fi
        INFO_PLIST="$SOURCE_APP/Contents/Info.plist"
        SOURCE_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
        SOURCE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
        SOURCE_EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST")"
        if [ "$SOURCE_BUNDLE_ID" != "$EXPECTED_BUNDLE_ID" ]; then
          echo "Unexpected bundle identifier: $SOURCE_BUNDLE_ID" >&2
          exit 1
        fi
        if [ "$SOURCE_VERSION" != "$EXPECTED_VERSION" ]; then
          echo "Unexpected bundle version: $SOURCE_VERSION" >&2
          exit 1
        fi
        if [ "$SOURCE_EXECUTABLE" != "$EXPECTED_EXECUTABLE" ] || [ ! -x "$SOURCE_APP/Contents/MacOS/$EXPECTED_EXECUTABLE" ]; then
          echo "Unexpected or missing app executable: $SOURCE_EXECUTABLE" >&2
          exit 1
        fi
        codesign --verify --deep --strict "$SOURCE_APP"

        echo "Copying update into staging path"
        rm -rf "$UPDATE_PATH"
        ditto "$SOURCE_APP" "$UPDATE_PATH"

        if [ -d "$APP_PATH" ]; then
          echo "Moving existing app to backup: $BACKUP_PATH"
          mv "$APP_PATH" "$BACKUP_PATH"
        fi

        if mv "$UPDATE_PATH" "$APP_PATH"; then
          echo "Opening updated app"
          open "$APP_PATH"
          echo "Update helper completed"
        else
          if [ -d "$BACKUP_PATH" ] && [ ! -d "$APP_PATH" ]; then
            mv "$BACKUP_PATH" "$APP_PATH"
          fi
          exit 1
        fi
        """#
    }
}

enum AppRelaunchInstallerError: Error, LocalizedError {
    case untrustedDownloadURL
    case checksumUnavailable
    case checksumMismatch
    case downloadFailed
    case notRunningFromAppBundle
    case appPathNotWritable(String)

    var errorDescription: String? {
        switch self {
        case .untrustedDownloadURL:
            "Update download URL is not trusted."
        case .checksumUnavailable:
            "Update checksum is unavailable."
        case .checksumMismatch:
            "Downloaded update checksum does not match."
        case .downloadFailed:
            "Update download failed."
        case .notRunningFromAppBundle:
            "Automatic updates require a packaged app build."
        case .appPathNotWritable(let path):
            "Cannot replace app at \(path). Move Automate Scripts to a writable location or install manually."
        }
    }
}

private extension String {
    func trimmingLeadingV() -> String {
        guard hasPrefix("v") || hasPrefix("V") else { return self }
        return String(dropFirst())
    }
}
