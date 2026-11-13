import Foundation

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

struct PowerActions: PowerActionsExecuting {
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
            return LaunchCommand(
                launchPath: "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession",
                arguments: ["-suspend"]
            )
        }
    }

    func perform(_ action: PowerAction) throws {
        let command = PowerActions.command(for: action)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.launchPath)
        process.arguments = command.arguments
        try process.run()
        process.waitUntilExit()
    }
}
