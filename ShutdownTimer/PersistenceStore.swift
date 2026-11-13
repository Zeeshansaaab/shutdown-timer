import Foundation

struct PersistedSettings: Codable, Equatable {
    var action: PowerAction
    var durationMinutes: Int
    var dailyEnabled: Bool
    var dailyHour: Int
    var dailyMinute: Int
    var launchAtLogin: Bool

    static let defaults = PersistedSettings(
        action: .sleep,
        durationMinutes: 15,
        dailyEnabled: false,
        dailyHour: 23,
        dailyMinute: 0,
        launchAtLogin: false
    )
}

final class PersistenceStore {
    private let defaults: UserDefaults
    private let key = "com.zeeshan.ShutdownTimer.settings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> PersistedSettings {
        guard
            let data = defaults.data(forKey: key),
            let settings = try? JSONDecoder().decode(PersistedSettings.self, from: data)
        else {
            return .defaults
        }
        return settings
    }

    func save(_ settings: PersistedSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
