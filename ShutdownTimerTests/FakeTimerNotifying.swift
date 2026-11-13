import Foundation
@testable import ShutdownTimer

final class FakeTimerNotifying: TimerNotifying {
    private(set) var warningCount = 0
    private(set) var permissionErrorCount = 0

    func postWarning(for action: PowerAction) {
        warningCount += 1
    }

    func postPermissionError(for action: PowerAction) {
        permissionErrorCount += 1
    }
}
