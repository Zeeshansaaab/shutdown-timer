import XCTest
@testable import ShutdownTimer

final class DailyScheduleTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testNextFireDateLaterTodayReturnsToday() {
        let now = date(year: 2026, month: 11, day: 13, hour: 10, minute: 0)
        let result = DailySchedule.nextFireDate(hour: 23, minute: 30, after: now, calendar: calendar)
        XCTAssertEqual(result, date(year: 2026, month: 11, day: 13, hour: 23, minute: 30))
    }

    func testNextFireDateEarlierTodayReturnsTomorrow() {
        let now = date(year: 2026, month: 11, day: 13, hour: 10, minute: 0)
        let result = DailySchedule.nextFireDate(hour: 9, minute: 0, after: now, calendar: calendar)
        XCTAssertEqual(result, date(year: 2026, month: 11, day: 14, hour: 9, minute: 0))
    }

    // Review Focus: target time exactly equal to "now" must resolve to tomorrow.
    func testNextFireDateExactlyNowReturnsTomorrow() {
        let now = date(year: 2026, month: 11, day: 13, hour: 10, minute: 0)
        let result = DailySchedule.nextFireDate(hour: 10, minute: 0, after: now, calendar: calendar)
        XCTAssertEqual(result, date(year: 2026, month: 11, day: 14, hour: 10, minute: 0))
    }

    func testStartDailyOnEngineArmsRunningStateWithComputedFireDate() {
        let now = date(year: 2026, month: 11, day: 13, hour: 10, minute: 0)
        let engine = TimerEngine(powerActions: FakePowerActions(), notifier: FakeTimerNotifying(), clock: { now })

        engine.startDaily(action: .sleep, hour: 23, minute: 0)

        XCTAssertEqual(
            engine.state,
            .running(action: .sleep, fireDate: date(year: 2026, month: 11, day: 13, hour: 23, minute: 0), isDaily: true)
        )
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components)!
    }
}
