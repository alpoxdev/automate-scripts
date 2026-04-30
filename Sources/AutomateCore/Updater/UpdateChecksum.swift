import CryptoKit
import Foundation

public struct UpdateChecksum: Equatable, Sendable {
    public let algorithm: String
    public let hexDigest: String

    public init?(digest: String?) {
        guard let digest else { return nil }
        let parts = digest.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0].lowercased() == "sha256", Self.isValidSHA256(parts[1]) else {
            return nil
        }
        self.algorithm = "sha256"
        self.hexDigest = parts[1].lowercased()
    }

    public init?(sidecarContents: String) {
        let firstToken = sidecarContents
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .first
            .map(String.init)
        guard let firstToken, Self.isValidSHA256(firstToken) else { return nil }
        self.algorithm = "sha256"
        self.hexDigest = firstToken.lowercased()
    }

    public func verify(data: Data) -> Bool {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return digest == hexDigest
    }

    private static func isValidSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isHexDigit }
    }
}
