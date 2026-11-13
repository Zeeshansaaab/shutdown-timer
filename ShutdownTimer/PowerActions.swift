import Foundation
import os

enum PowerAction: String, CaseIterable, Codable, Identifiable {
    case sleep
    case shutDown
    case lock

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sleep: return "Sleep"
        case .shutDown: return "Shut Down"
        case .lock: return "Lock Screen"
        }
    }
}

protocol PowerActionsExecuting {
    func perform(_ action: PowerAction) throws
}

struct LaunchCommand: Equatable {
    let launchPath: String
    let arguments: [String]
}

struct PowerActionError: Error, CustomStringConvertible {
    let context: String
    let exitCode: Int32
    let stderr: String

    var description: String {
        "\(context) exited \(exitCode): \(stderr)"
    }
}

struct PowerActions: PowerActionsExecuting {
    private static let logger = Logger(subsystem: "com.zeeshan.ShutdownTimer", category: "PowerActions")
    private static let defaultTimeout: TimeInterval = 10

    static func command(for action: PowerAction) -> LaunchCommand {
        switch action {
        case .sleep:
            return LaunchCommand(launchPath: "/usr/bin/pmset", arguments: ["sleepnow"])
        case .shutDown:
            return LaunchCommand(
                launchPath: "/usr/bin/osascript",
                arguments: ["-e", "tell application \"System Events\" to shut down"]
            )
        case .lock:
            // CGSession (the historical mechanism) no longer ships on current macOS;
            // this simulates the real Lock Screen keyboard shortcut instead.
            return LaunchCommand(
                launchPath: "/usr/bin/osascript",
                arguments: ["-e", "tell application \"System Events\" to keystroke \"q\" using {control down, command down}"]
            )
        }
    }

    func perform(_ action: PowerAction) throws {
        try Self.execute(PowerActions.command(for: action), context: action.rawValue)
    }

    @discardableResult
    static func execute(_ command: LaunchCommand, context: String, timeout: TimeInterval = defaultTimeout) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.launchPath)
        process.arguments = command.arguments

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            logger.error("\(context, privacy: .public) timed out after \(timeout, privacy: .public)s")
            throw PowerActionError(context: context, exitCode: -1, stderr: "timed out after \(timeout)s")
        }

        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrString = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            logger.error("\(context, privacy: .public) exited \(process.terminationStatus, privacy: .public): \(stderrString, privacy: .public)")
            throw PowerActionError(context: context, exitCode: process.terminationStatus, stderr: stderrString)
        }

        return stderrString
    }
}
