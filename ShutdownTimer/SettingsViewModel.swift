import Foundation
import Combine

final class SettingsViewModel: ObservableObject {
    @Published var action: PowerAction {
        didSet {
            persist()
            if dailyEnabled { armDailySchedule() }
        }
    }
    @Published var durationMinutes: Int
    @Published var dailyEnabled: Bool {
        didSet { handleDailyToggle() }
    }
    @Published var dailyTime: Date {
        didSet {
            persist()
            if dailyEnabled { armDailySchedule() }
        }
    }
    @Published private(set) var launchAtLogin: Bool

    private let store: PersistenceStore
    private let loginItemManager: LoginItemManaging
    private weak var engine: TimerEngine?

    init(store: PersistenceStore, loginItemManager: LoginItemManaging) {
        self.store = store
        self.loginItemManager = loginItemManager

        let settings = store.load()
        action = settings.action
        durationMinutes = settings.durationMinutes
        dailyEnabled = settings.dailyEnabled
        // The login item's real registration status is the source of truth —
        // not the mirrored UserDefaults value, which can drift from it.
        launchAtLogin = loginItemManager.isEnabled

        var components = DateComponents()
        components.hour = settings.dailyHour
        components.minute = settings.dailyMinute
        dailyTime = Calendar.current.date(from: components) ?? Date()
    }

    func attach(engine: TimerEngine) {
        self.engine = engine
        // Independent of the one-off countdown: whenever the engine returns to
        // idle (a one-off finished/was cancelled) and the daily schedule is
        // enabled, re-arm it so it's never silently orphaned. Called after
        // `state` has already settled to `.idle` — never during `@Published`'s
        // own willSet — so the re-arm's own state write isn't stomped by the
        // transition that triggered it.
        engine.onBecameIdle = { [weak self] in
            guard let self, self.dailyEnabled else { return }
            self.armDailySchedule()
        }
        if dailyEnabled {
            armDailySchedule()
        }
    }

    func startTimer(using engine: TimerEngine) {
        persist()
        engine.start(action: action, duration: TimeInterval(durationMinutes * 60))
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        let succeeded = loginItemManager.setEnabled(enabled)
        launchAtLogin = succeeded ? enabled : loginItemManager.isEnabled
        persist()
    }

    private func handleDailyToggle() {
        persist()
        if dailyEnabled {
            armDailySchedule()
        } else if let engine, engine.state.isDaily {
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
