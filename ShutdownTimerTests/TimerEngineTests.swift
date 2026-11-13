import XCTest
@testable import ShutdownTimer

final class TimerEngineTests: XCTestCase {
    private final class TestClock {
        var currentDate: Date
        init(_ date: Date) { currentDate = date }
        func now() -> Date { currentDate }
    }

    private func makeEngine(
        clock: TestClock,
        notifier: FakeTimerNotifying,
        powerActions: FakePowerActions
    ) -> TimerEngine {
        TimerEngine(powerActions: powerActions, notifier: notifier, clock: clock.now)
    }

    func testStartSetsRunningStateWithFireDate() {
        let clock = TestClock(Date(timeIntervalSince1970: 0))
        let engine = makeEngine(clock: clock, notifier: FakeTimerNotifying(), powerActions: FakePowerActions())

        engine.start(action: .sleep, duration: 900)

        XCTAssertEqual(
            engine.state,
            .running(action: .sleep, fireDate: Date(timeIntervalSince1970: 900), isDaily: false)
        )
    }

    func testTickBeforeWarningWindowDoesNothing() {
        let clock = TestClock(Date(timeIntervalSince1970: 0))
        let notifier = FakeTimerNotifying()
        let engine = makeEngine(clock: clock, notifier: notifier, powerActions: FakePowerActions())
        engine.start(action: .sleep, duration: 900)

        clock.currentDate = Date(timeIntervalSince1970: 800)
        engine.tick()

        XCTAssertEqual(notifier.warningCount, 0)
        XCTAssertEqual(
            engine.state,
            .running(action: .sleep, fireDate: Date(timeIntervalSince1970: 900), isDaily: false)
        )
    }

    func testTickEntersWarningWindowOnce() {
        let clock = TestClock(Date(timeIntervalSince1970: 0))
        let notifier = FakeTimerNotifying()
        let engine = makeEngine(clock: clock, notifier: notifier, powerActions: FakePowerActions())
        engine.start(action: .sleep, duration: 900)

        clock.currentDate = Date(timeIntervalSince1970: 850) // 50s left, inside the 60s window
        engine.tick()
        engine.tick() // must not re-post

        XCTAssertEqual(notifier.warningCount, 1)
        XCTAssertEqual(
            engine.state,
            .warningShown(action: .sleep, fireDate: Date(timeIntervalSince1970: 900), isDaily: false)
        )
    }

    func testTickFiresActionAtFireDateAndReturnsToIdleForOneOff() {
        let clock = TestClock(Date(timeIntervalSince1970: 0))
        let powerActions = FakePowerActions()
        let engine = makeEngine(clock: clock, notifier: FakeTimerNotifying(), powerActions: powerActions)
        engine.start(action: .lock, duration: 900)

        clock.currentDate = Date(timeIntervalSince1970: 900)
        engine.tick()

        XCTAssertEqual(powerActions.performedActions, [.lock])
        XCTAssertEqual(engine.state, .idle)
    }

    func testTickFiresDailyActionAndReschedulesTomorrow() {
        let start = Date(timeIntervalSince1970: 0)
        let clock = TestClock(start)
        let powerActions = FakePowerActions()
        let engine = makeEngine(clock: clock, notifier: FakeTimerNotifying(), powerActions: powerActions)
        engine.startAt(action: .sleep, fireDate: start, isDaily: true)

        engine.tick()

        XCTAssertEqual(powerActions.performedActions, [.sleep])
        guard case .running(let action, let fireDate, let isDaily) = engine.state else {
            return XCTFail("expected running state after daily fire")
        }
        XCTAssertEqual(action, .sleep)
        XCTAssertTrue(isDaily)
        XCTAssertEqual(fireDate, Calendar.current.date(byAdding: .day, value: 1, to: start))
    }

    func testFireWithThrowingPowerActionsFallsBackToIdleAndReportsError() {
        let clock = TestClock(Date(timeIntervalSince1970: 0))
        let notifier = FakeTimerNotifying()
        let powerActions = FakePowerActions()
        powerActions.errorToThrow = NSError(domain: "test", code: 1)
        let engine = makeEngine(clock: clock, notifier: notifier, powerActions: powerActions)
        engine.startAt(action: .shutDown, fireDate: Date(timeIntervalSince1970: 0), isDaily: true)

        engine.tick()

        XCTAssertEqual(notifier.permissionErrorCount, 1)
        XCTAssertEqual(engine.state, .idle)
    }

    func testCancelFromRunningReturnsToIdle() {
        let clock = TestClock(Date(timeIntervalSince1970: 0))
        let engine = makeEngine(clock: clock, notifier: FakeTimerNotifying(), powerActions: FakePowerActions())
        engine.start(action: .sleep, duration: 900)

        engine.cancel()

        XCTAssertEqual(engine.state, .idle)
    }

    // Review Focus: cancel while already idle must stay idle, not throw/crash.
    func testCancelWhileIdleStaysIdle() {
        let clock = TestClock(Date(timeIntervalSince1970: 0))
        let engine = makeEngine(clock: clock, notifier: FakeTimerNotifying(), powerActions: FakePowerActions())

        engine.cancel()

        XCTAssertEqual(engine.state, .idle)
    }

    func testSnoozeFromWarningShownPushesFireDateAndReturnsToRunning() {
        let clock = TestClock(Date(timeIntervalSince1970: 0))
        let notifier = FakeTimerNotifying()
        let engine = makeEngine(clock: clock, notifier: notifier, powerActions: FakePowerActions())
        engine.start(action: .sleep, duration: 900)
        clock.currentDate = Date(timeIntervalSince1970: 850)
        engine.tick() // enters warningShown

        engine.snooze(by: 600)

        XCTAssertEqual(
            engine.state,
            .running(action: .sleep, fireDate: Date(timeIntervalSince1970: 1500), isDaily: false)
        )

        clock.currentDate = Date(timeIntervalSince1970: 900)
        engine.tick()
        XCTAssertEqual(
            engine.state,
            .running(action: .sleep, fireDate: Date(timeIntervalSince1970: 1500), isDaily: false)
        )
    }

    // Review Focus: snooze while idle (not warningShown) must be a no-op.
    func testSnoozeWhileIdleIsNoOp() {
        let clock = TestClock(Date(timeIntervalSince1970: 0))
        let engine = makeEngine(clock: clock, notifier: FakeTimerNotifying(), powerActions: FakePowerActions())

        engine.snooze()

        XCTAssertEqual(engine.state, .idle)
    }

    // Review Focus: out-of-range custom duration is clamped, never zero-length or multi-day.
    func testStartClampsOutOfRangeDurations() {
        let clock = TestClock(Date(timeIntervalSince1970: 0))
        let engine = makeEngine(clock: clock, notifier: FakeTimerNotifying(), powerActions: FakePowerActions())

        engine.start(action: .sleep, duration: -30)
        XCTAssertEqual(
            engine.state,
            .running(action: .sleep, fireDate: Date(timeIntervalSince1970: TimerEngine.minimumDuration), isDaily: false)
        )

        engine.start(action: .sleep, duration: 99 * 60 * 60) // 99h, over the 24h cap
        XCTAssertEqual(
            engine.state,
            .running(action: .sleep, fireDate: Date(timeIntervalSince1970: TimerEngine.maximumDuration), isDaily: false)
        )
    }
}
