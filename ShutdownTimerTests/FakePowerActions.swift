import Foundation
@testable import ShutdownTimer

final class FakePowerActions: PowerActionsExecuting {
    private(set) var performedActions: [PowerAction] = []
    var errorToThrow: Error?

    func perform(_ action: PowerAction) throws {
        if let error = errorToThrow {
            throw error
        }
        performedActions.append(action)
    }
}
