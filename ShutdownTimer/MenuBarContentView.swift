import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var engine: TimerEngine
    @ObservedObject var settingsStore: SettingsViewModel

    private let presets = [15, 30, 60, 90]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Action", selection: $settingsStore.action) {
                ForEach(PowerAction.allCases) { action in
                    Text(action.displayName).tag(action)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 6) {
                ForEach(presets, id: \.self) { minutes in
                    Button("\(minutes)m") {
                        settingsStore.durationMinutes = minutes
                    }
                    .buttonStyle(.bordered)
                    .tint(settingsStore.durationMinutes == minutes ? Color.accentColor : Color.secondary)
                }
                Stepper("\(settingsStore.durationMinutes)m", value: $settingsStore.durationMinutes, in: 1...1440)
                    .fixedSize()
            }

            startCancelButton

            Divider()

            Toggle("Enable daily schedule", isOn: $settingsStore.dailyEnabled)
            if settingsStore.dailyEnabled {
                DatePicker("Daily time", selection: $settingsStore.dailyTime, displayedComponents: .hourAndMinute)
            }

            Divider()

            Toggle(
                "Launch at Login",
                isOn: Binding(
                    get: { settingsStore.launchAtLogin },
                    set: { settingsStore.setLaunchAtLogin($0) }
                )
            )

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 320)
    }

    @ViewBuilder
    private var startCancelButton: some View {
        switch engine.state {
        case .idle:
            Button("Start") {
                settingsStore.startTimer(using: engine)
            }
        case .running(let action, let fireDate, _), .warningShown(let action, let fireDate, _):
            Button("Cancel (\(action.displayName) at \(fireDate.formatted(date: .omitted, time: .shortened)))") {
                engine.cancel()
            }
        }
    }
}
