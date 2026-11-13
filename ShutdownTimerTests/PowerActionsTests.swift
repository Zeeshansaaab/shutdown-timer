import XCTest
@testable import ShutdownTimer

final class PowerActionsTests: XCTestCase {
    func testSleepCommand() {
        let command = PowerActions.command(for: .sleep)
        XCTAssertEqual(command, LaunchCommand(launchPath: "/usr/bin/pmset", arguments: ["sleepnow"]))
    }

    func testShutDownCommand() {
        let command = PowerActions.command(for: .shutDown)
        XCTAssertEqual(
            command,
            LaunchCommand(
                launchPath: "/usr/bin/osascript",
                arguments: ["-e", "tell application \"System Events\" to shut down"]
            )
        )
    }

    func testLockCommand() {
        let command = PowerActions.command(for: .lock)
        XCTAssertEqual(
            command,
            LaunchCommand(
                launchPath: "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession",
                arguments: ["-suspend"]
            )
        )
    }
}
