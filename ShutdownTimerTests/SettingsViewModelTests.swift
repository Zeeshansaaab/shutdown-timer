import XCTest
@testable import ShutdownTimer

final class SettingsViewModelTests: XCTestCase {
    private final class TestClock {
        var currentDate: Date
        init(_ date: Date) { currentDate = date }
        func now() -> Date { currentDate }
    }

    private var defaults: UserDefaults!
    private var store: PersistenceStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "SettingsViewModelTests")
        defaults.removePersistentDomain(forName: "SettingsViewModelTests")
        store = PersistenceStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "SettingsViewModelTests")
        super.tearDown()
    }

    private func date(year: Int = 2026, month: Int = 11, day: Int = 13, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components)!
    }

    func testInitSeedsLaunchAtLoginFromLoginItemManagerNotUserDefaults() {
        // UserDefaults says off, but the real login-item registration says on —
        // the registration is the source of truth.
        store.save(PersistedSettings(action: .sleep, durationMinutes: 15, dailyEnabled: false, dailyHour: 23, dailyMinute: 0, launchAtLogin: false))
        let loginItemManager = FakeLoginItemManager()
        loginItemManager.isEnabled = true

        let viewModel = SettingsViewModel(store: store, loginItemManager: loginItemManager)

        XCTAssertTrue(viewModel.launchAtLogin)
    }

    func testChangingActionPersistsImmediately() {
        let viewModel = SettingsViewModel(store: store, loginItemManager: FakeLoginItemManager())

        viewModel.action = .lock

        XCTAssertEqual(store.load().action, .lock)
    }

    func testChangingDailyTimePersistsImmediately() {
        let viewModel = SettingsViewModel(store: store, loginItemManager: FakeLoginItemManager())

        viewModel.dailyTime = date(hour: 7, minute: 15)

        let saved = store.load()
        XCTAssertEqual(saved.dailyHour, 7)
        XCTAssertEqual(saved.dailyMinute, 15)
    }

    func testChangingDailyTimeWhileScheduleEnabledReArmsEngineWithNewTime() {
        let now = date(hour: 10, minute: 0)
        let clock = TestClock(now)
        let engine = TimerEngine(powerActions: FakePowerActions(), notifier: FakeTimerNotifying(), clock: clock.now)
        let viewModel = SettingsViewModel(store: store, loginItemManager: FakeLoginItemManager())
        viewModel.attach(engine: engine)
        viewModel.dailyEnabled = true
        viewModel.dailyTime = date(hour: 23, minute: 0)

        viewModel.dailyTime = date(hour: 22, minute: 0)

        guard case .running(_, let fireDate, let isDaily) = engine.state else {
            return XCTFail("expected engine to stay armed for the daily schedule")
        }
        XCTAssertTrue(isDaily)
        XCTAssertEqual(fireDate, date(hour: 22, minute: 0))
    }

    func testChangingActionWhileScheduleEnabledReArmsEngineWithNewAction() {
        let now = date(hour: 10, minute: 0)
        let clock = TestClock(now)
        let engine = TimerEngine(powerActions: FakePowerActions(), notifier: FakeTimerNotifying(), clock: clock.now)
        let viewModel = SettingsViewModel(store: store, loginItemManager: FakeLoginItemManager())
        viewModel.attach(engine: engine)
        viewModel.dailyEnabled = true

        viewModel.action = .shutDown

        guard case .running(let action, _, _) = engine.state else {
            return XCTFail("expected engine to stay armed for the daily schedule")
        }
        XCTAssertEqual(action, .shutDown)
    }

    func testDisablingScheduleWhileWarningShownCancelsEngine() {
        let now = date(hour: 10, minute: 0)
        let clock = TestClock(now)
        let engine = TimerEngine(powerActions: FakePowerActions(), notifier: FakeTimerNotifying(), clock: clock.now)
        let viewModel = SettingsViewModel(store: store, loginItemManager: FakeLoginItemManager())
        viewModel.attach(engine: engine)
        viewModel.dailyEnabled = true
        guard case .running(_, let fireDate, true) = engine.state else {
            return XCTFail("expected engine to be armed for the daily schedule")
        }

        // Move into the 60s warning window for the armed daily fire.
        clock.currentDate = fireDate.addingTimeInterval(-30)
        engine.tick()
        guard case .warningShown = engine.state else {
            return XCTFail("expected engine to be in warningShown before disabling")
        }

        viewModel.dailyEnabled = false

        XCTAssertEqual(engine.state, .idle)
    }

    func testOneOffTimerCompletingReArmsDailyScheduleIfStillEnabled() {
        let now = date(hour: 10, minute: 0)
        let clock = TestClock(now)
        let engine = TimerEngine(powerActions: FakePowerActions(), notifier: FakeTimerNotifying(), clock: clock.now)
        let viewModel = SettingsViewModel(store: store, loginItemManager: FakeLoginItemManager())
        viewModel.attach(engine: engine)
        viewModel.dailyEnabled = true
        viewModel.action = .sleep

        // Starting a one-off timer takes priority and collapses the daily arm.
        viewModel.startTimer(using: engine)
        guard case .running(_, let oneOffFireDate, let isDailyBeforeFire) = engine.state else {
            return XCTFail("expected one-off timer to be running")
        }
        XCTAssertFalse(isDailyBeforeFire)

        clock.currentDate = oneOffFireDate
        engine.tick()

        guard case .running(_, _, let isDailyAfterFire) = engine.state else {
            return XCTFail("expected the daily schedule to re-arm after the one-off timer completed")
        }
        XCTAssertTrue(isDailyAfterFire, "daily schedule must not be silently orphaned by a one-off timer")
    }

    func testSetLaunchAtLoginSuccessUpdatesPublishedValueAndPersists() {
        let loginItemManager = FakeLoginItemManager()
        let viewModel = SettingsViewModel(store: store, loginItemManager: loginItemManager)

        viewModel.setLaunchAtLogin(true)

        XCTAssertTrue(viewModel.launchAtLogin)
        XCTAssertEqual(loginItemManager.setEnabledCalls, [true])
        XCTAssertTrue(store.load().launchAtLogin)
    }

    func testSetLaunchAtLoginFailureRevertsPublishedValue() {
        let loginItemManager = FakeLoginItemManager()
        loginItemManager.shouldSucceed = false
        let viewModel = SettingsViewModel(store: store, loginItemManager: loginItemManager)
        XCTAssertFalse(viewModel.launchAtLogin)

        viewModel.setLaunchAtLogin(true)

        XCTAssertFalse(viewModel.launchAtLogin, "a failed registration must revert the toggle, not leave it showing ON")
    }
}
