import Foundation

enum TimerState: Equatable {
    case idle
    case running(action: PowerAction, fireDate: Date, isDaily: Bool)
    case warningShown(action: PowerAction, fireDate: Date, isDaily: Bool)
}

protocol TimerNotifying {
    func postWarning(for action: PowerAction)
    func postPermissionError(for action: PowerAction)
}

final class TimerEngine: ObservableObject {
    @Published private(set) var state: TimerState = .idle

    static let warningLeadTime: TimeInterval = 60
    static let minimumDuration: TimeInterval = 60
    static let maximumDuration: TimeInterval = 24 * 60 * 60

    private let powerActions: PowerActionsExecuting
    private let notifier: TimerNotifying
    let clock: () -> Date
    private var warningPosted = false

    init(
        powerActions: PowerActionsExecuting,
        notifier: TimerNotifying,
        clock: @escaping () -> Date = { Date() }
    ) {
        self.powerActions = powerActions
        self.notifier = notifier
        self.clock = clock
    }

    func start(action: PowerAction, duration: TimeInterval, isDaily: Bool = false) {
        let clamped = min(max(duration, Self.minimumDuration), Self.maximumDuration)
        let fireDate = clock().addingTimeInterval(clamped)
        startAt(action: action, fireDate: fireDate, isDaily: isDaily)
    }

    func startAt(action: PowerAction, fireDate: Date, isDaily: Bool) {
        warningPosted = false
        state = .running(action: action, fireDate: fireDate, isDaily: isDaily)
    }

    func cancel() {
        warningPosted = false
        state = .idle
    }

    func snooze(by interval: TimeInterval = 10 * 60) {
        guard case .warningShown(let action, let fireDate, let isDaily) = state else {
            return
        }
        warningPosted = false
        state = .running(action: action, fireDate: fireDate.addingTimeInterval(interval), isDaily: isDaily)
    }

    func tick() {
        let now = clock()

        switch state {
        case .idle:
            return

        case .running(let action, let fireDate, let isDaily):
            if now >= fireDate {
                fire(action: action, fireDate: fireDate, isDaily: isDaily)
            } else if now >= fireDate.addingTimeInterval(-Self.warningLeadTime), !warningPosted {
                warningPosted = true
                notifier.postWarning(for: action)
                state = .warningShown(action: action, fireDate: fireDate, isDaily: isDaily)
            }

        case .warningShown(let action, let fireDate, let isDaily):
            if now >= fireDate {
                fire(action: action, fireDate: fireDate, isDaily: isDaily)
            }
        }
    }

    private func fire(action: PowerAction, fireDate: Date, isDaily: Bool) {
        do {
            try powerActions.perform(action)
        } catch {
            notifier.postPermissionError(for: action)
            warningPosted = false
            state = .idle
            return
        }

        if isDaily {
            let nextFireDate = Calendar.current.date(byAdding: .day, value: 1, to: fireDate)
                ?? fireDate.addingTimeInterval(24 * 60 * 60)
            warningPosted = false
            state = .running(action: action, fireDate: nextFireDate, isDaily: true)
        } else {
            warningPosted = false
            state = .idle
        }
    }
}
