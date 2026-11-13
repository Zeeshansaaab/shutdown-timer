import Foundation
import Combine

final class SettingsViewModel: ObservableObject {
    @Published var action: PowerAction
    @Published var durationMinutes: Int
    @Published var dailyEnabled: Bool {
        didSet { handleDailyToggle() }
    }
    @Published var dailyTime: Date
    @Published var launchAtLogin: Bool {
        didSet { loginItemManager.setEnabled(launchAtLogin) }
    }

    private let store: PersistenceStore
    private let loginItemManager: LoginItemManager
    private weak var engine: TimerEngine?

    init(store: PersistenceStore, loginItemManager: LoginItemManager) {
        self.store = store
        self.loginItemManager = loginItemManager

        let settings = store.load()
        action = settings.action
        durationMinutes = settings.durationMinutes
        dailyEnabled = settings.dailyEnabled
        launchAtLogin = settings.launchAtLogin

        var components = DateComponents()
        components.hour = settings.dailyHour
        components.minute = settings.dailyMinute
        dailyTime = Calendar.current.date(from: components) ?? Date()
    }

    func attach(engine: TimerEngine) {
        self.engine = engine
        if dailyEnabled {
            armDailySchedule()
        }
    }

    func startTimer(using engine: TimerEngine) {
        persist()
        engine.start(action: action, duration: TimeInterval(durationMinutes * 60))
    }

    private func handleDailyToggle() {
        persist()
        if dailyEnabled {
            armDailySchedule()
        } else if let engine, case .running(_, _, true) = engine.state {
            engine.cancel()
        }
    }

    private func armDailySchedule() {
        guard let engine else { return }
        let components = Calendar.current.dateComponents([.hour, .minute], from: dailyTime)
        engine.startDaily(action: action, hour: components.hour ?? 0, minute: components.minute ?? 0)
    }

    private func persist() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: dailyTime)
        let settings = PersistedSettings(
            action: action,
            durationMinutes: durationMinutes,
            dailyEnabled: dailyEnabled,
            dailyHour: components.hour ?? 0,
            dailyMinute: components.minute ?? 0,
            launchAtLogin: launchAtLogin
        )
        store.save(settings)
    }
}
