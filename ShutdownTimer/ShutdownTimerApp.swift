import SwiftUI

@main
struct ShutdownTimerApp: App {
    @StateObject private var engine: TimerEngine
    @StateObject private var settingsStore: SettingsViewModel
    private let notificationManager: NotificationManager

    init() {
        let store = PersistenceStore()
        let manager = NotificationManager()
        let timerEngine = TimerEngine(powerActions: PowerActions(), notifier: manager)
        let viewModel = SettingsViewModel(store: store, loginItemManager: LoginItemManager())

        manager.onCancel = { [weak timerEngine] in timerEngine?.cancel() }
        manager.onSnooze = { [weak timerEngine] in timerEngine?.snooze() }
        manager.requestAuthorization()

        viewModel.attach(engine: timerEngine)

        _engine = StateObject(wrappedValue: timerEngine)
        _settingsStore = StateObject(wrappedValue: viewModel)
        notificationManager = manager
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(engine: engine, settingsStore: settingsStore)
        } label: {
            MenuBarLabel(engine: engine)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var engine: TimerEngine
    @State private var now = Date()

    // Display-only: TimerEngine owns its own timer and drives `tick()` itself,
    // so this is purely redrawing the countdown text every second — it has no
    // bearing on whether the engine actually fires.
    private let redrawTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            switch engine.state {
            case .idle:
                Image(systemName: "moon.zzz")
            case .running(_, let fireDate, _), .warningShown(_, let fireDate, _):
                Text(countdownText(until: fireDate))
            }
        }
        .onReceive(redrawTicker) { tick in
            now = tick
        }
    }

    private func countdownText(until fireDate: Date) -> String {
        let remaining = max(0, Int(fireDate.timeIntervalSince(now)))
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        let seconds = remaining % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
