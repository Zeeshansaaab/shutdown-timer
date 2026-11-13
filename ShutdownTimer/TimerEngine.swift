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
    static let missedFireGrace: TimeInterval = 5 * 60

    private let powerActions: PowerActionsExecuting
    private let notifier: TimerNotifying
    let clock: () -> Date
    private var warningPosted = false

    /// Called after `state` has fully settled to `.idle` (never while a daily
    /// schedule reschedules itself). Called synchronously, after the `state`
    /// assignment has completed — never from within a Combine subscriber to
    /// `$state`, which would reenter the property's willSet and have this
    /// callback's own state write silently stomped by the outer assignment.
    var onBecameIdle: (() -> Void)?

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
        onBecameIdle?()
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
        let now = clock()
        warningPosted = false

        // A wildly overdue fire (the Mac was asleep/suspended through the scheduled
        // time, not just ticking a few seconds late) must not execute the stale
        // action, and a daily schedule must reschedule from `now`, not from the
        // stale `fireDate` — rescheduling from `fireDate` would land in the past
        // again and re-fire on the very next tick, once per missed day.
        guard now.timeIntervalSince(fireDate) <= Self.missedFireGrace else {
            if isDaily {
                state = .running(action: action, fireDate: nextDailyFireDate(after: now, basedOn: fireDate), isDaily: true)
            } else {
                state = .idle
                onBecameIdle?()
            }
            return
        }

        do {
            try powerActions.perform(action)
        } catch {
            notifier.postPermissionError(for: action)
            if isDaily {
                state = .running(action: action, fireDate: nextDailyFireDate(after: clock(), basedOn: fireDate), isDaily: true)
            } else {
                state = .idle
                onBecameIdle?()
            }
            return
        }

        if isDaily {
            state = .running(action: action, fireDate: nextDailyFireDate(after: clock(), basedOn: fireDate), isDaily: true)
        } else {
            state = .idle
            onBecameIdle?()
        }
    }

    private func nextDailyFireDate(after now: Date, basedOn fireDate: Date) -> Date {
        let components = Calendar.current.dateComponents([.hour, .minute], from: fireDate)
        return DailySchedule.nextFireDate(hour: components.hour ?? 0, minute: components.minute ?? 0, after: now)
    }
}

extension TimerState {
    var isDaily: Bool {
        switch self {
        case .idle:
            return false
        case .running(_, _, let isDaily), .warningShown(_, _, let isDaily):
            return isDaily
        }
    }
}

extension TimerEngine {
    func startDaily(action: PowerAction, hour: Int, minute: Int) {
        let fireDate = DailySchedule.nextFireDate(hour: hour, minute: minute, after: clock())
        startAt(action: action, fireDate: fireDate, isDaily: true)
    }
}
