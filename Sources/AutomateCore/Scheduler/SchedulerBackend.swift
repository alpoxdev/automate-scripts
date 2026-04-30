import Foundation

public protocol SchedulerBackend {
    func sync(jobs: [ScriptJob], dryRun: Bool) throws -> SchedulerSyncPlan
}

public struct SchedulerSyncPlan: Codable, Equatable, Sendable {
    public var createdOrUpdated: [String]
    public var removed: [String]
    public var skipped: [String]
    public var dryRun: Bool

    public init(createdOrUpdated: [String] = [], removed: [String] = [], skipped: [String] = [], dryRun: Bool) {
        self.createdOrUpdated = createdOrUpdated
        self.removed = removed
        self.skipped = skipped
        self.dryRun = dryRun
    }

    public var summary: String {
        "create/update=\(createdOrUpdated.count), remove=\(removed.count), skipped=\(skipped.count), dryRun=\(dryRun)"
    }
}
