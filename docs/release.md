# Release

Public alpha checklist:

- `swift test` passes.
- `swift build --product automate` passes.
- Menu bar app builds on the supported Xcode/macOS version.
- README examples work on a clean checkout.
- No secrets or local absolute paths are committed.
- LICENSE, SECURITY, CONTRIBUTING, and issue templates exist.

## In-app update contract

- Release tags must use semantic `vX.Y.Z` format.
- Published DMG assets must be named:
  - `AutomateScripts-vX.Y.Z-macos-arm64.dmg`
  - `AutomateScripts-vX.Y.Z-macos-x86_64.dmg`
- Each DMG must have a matching `.sha256` sidecar uploaded to the same GitHub Release.
- The packaged `Automate Scripts.app/Contents/Info.plist` must set `CFBundleShortVersionString` to `X.Y.Z`; the in-app updater compares this value with the GitHub latest release tag.
- The updater only auto-installs when running from a writable `.app` bundle; source/debug builds and non-writable installs must use manual installation.
