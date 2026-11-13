import Foundation
@testable import ShutdownTimer

final class FakeLoginItemManager: LoginItemManaging {
    var isEnabled: Bool = false
    var shouldSucceed = true
    private(set) var setEnabledCalls: [Bool] = []

    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        setEnabledCalls.append(enabled)
        guard shouldSucceed else { return false }
        isEnabled = enabled
        return true
    }
}
