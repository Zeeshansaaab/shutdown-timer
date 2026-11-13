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
        // CGSession (the historical lock mechanism) no longer ships on current macOS;
        // this simulates the real Lock Screen keyboard shortcut via System Events instead.
        let command = PowerActions.command(for: .lock)
        XCTAssertEqual(
            command,
            LaunchCommand(
                launchPath: "/usr/bin/osascript",
                arguments: ["-e", "tell application \"System Events\" to keystroke \"q\" using {control down, command down}"]
            )
        )
    }

    func testExecuteSucceedsOnZeroExit() {
        let command = LaunchCommand(launchPath: "/usr/bin/true", arguments: [])
        XCTAssertNoThrow(try PowerActions.execute(command, context: "test"))
    }

    func testExecuteThrowsOnNonZeroExit() {
        let command = LaunchCommand(launchPath: "/usr/bin/false", arguments: [])
        XCTAssertThrowsError(try PowerActions.execute(command, context: "test")) { error in
            guard let actionError = error as? PowerActionError else {
                return XCTFail("expected PowerActionError, got \(error)")
            }
            XCTAssertEqual(actionError.exitCode, 1)
        }
    }

    func testExecuteCapturesStderrOnFailure() {
        let command = LaunchCommand(launchPath: "/bin/sh", arguments: ["-c", "echo boom 1>&2; exit 3"])
        XCTAssertThrowsError(try PowerActions.execute(command, context: "test")) { error in
            guard let actionError = error as? PowerActionError else {
                return XCTFail("expected PowerActionError, got \(error)")
            }
            XCTAssertEqual(actionError.exitCode, 3)
            XCTAssertTrue(actionError.stderr.contains("boom"))
        }
    }
}
