import ServiceManagement
import os

protocol LoginItemManaging {
    var isEnabled: Bool { get }
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool
}

final class LoginItemManager: LoginItemManaging {
    private let logger = Logger(subsystem: "com.zeeshan.ShutdownTimer", category: "LoginItemManager")

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            logger.error("Failed to \(enabled ? "register" : "unregister") login item: \(error.localizedDescription)")
            return false
        }
    }
}
