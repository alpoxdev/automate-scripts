import Foundation

public struct AppVersion: Equatable, Sendable {
    public let displayText: String
    public let semanticVersion: SemanticVersion?

    public init(displayText: String, semanticVersion: SemanticVersion?) {
        self.displayText = displayText
        self.semanticVersion = semanticVersion
    }

    public static func current(bundle: Bundle = .main) -> AppVersion {
        let rawVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard let rawVersion, !rawVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AppVersion(displayText: "dev", semanticVersion: nil)
        }
        let version = SemanticVersion(rawVersion)
        return AppVersion(displayText: version?.tagDescription ?? rawVersion, semanticVersion: version)
    }
}
