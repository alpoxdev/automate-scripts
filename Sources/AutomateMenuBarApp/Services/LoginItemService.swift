import AppKit
import AutomateCore
import Foundation
#if canImport(ServiceManagement)
import ServiceManagement
#endif

enum LoginItemState: Equatable {
    case enabled
    case disabled
    case requiresApproval
    case notRegistered
    case unsupported
    case unknown(String)

    var isEnabled: Bool {
        if case .enabled = self { return true }
        return false
    }

    func title(localizer: Localizer) -> String {
        switch self {
        case .enabled: localizer.text("login.status.enabled")
        case .disabled: localizer.text("login.status.disabled")
        case .requiresApproval: localizer.text("login.status.requiresApproval")
        case .notRegistered: localizer.text("login.status.notRegistered")
        case .unsupported: localizer.text("login.status.unsupported")
        case .unknown(let value): String(format: localizer.text("login.status.unknown"), value)
        }
    }

    var needsUserAction: Bool {
        if case .requiresApproval = self { return true }
        return false
    }
}

struct LoginItemService {
    func state() -> LoginItemState {
        #if canImport(ServiceManagement)
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled: return .enabled
            case .notRegistered: return .notRegistered
            case .notFound: return .disabled
            case .requiresApproval: return .requiresApproval
            @unknown default: return .unknown(String(describing: SMAppService.mainApp.status))
            }
        }
        #endif
        return .unsupported
    }

    func status() -> Bool {
        state().isEnabled
    }

    func setEnabled(_ enabled: Bool) throws {
        #if canImport(ServiceManagement)
        if #available(macOS 13.0, *) {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            return
        }
        #endif
        throw LoginItemError.unsupported
    }

    func openLoginItemsSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.Users-Groups-Settings.extension?LoginItems"
        ]
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) { return }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}

enum LoginItemError: Error, LocalizedError {
    case unsupported

    var errorDescription: String? {
        switch self {
        case .unsupported: "Login item registration requires macOS 13 or later."
        }
    }
}
