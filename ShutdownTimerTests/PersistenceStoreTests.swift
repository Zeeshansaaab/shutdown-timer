import XCTest
@testable import ShutdownTimer

final class PersistenceStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: PersistenceStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "PersistenceStoreTests")
        defaults.removePersistentDomain(forName: "PersistenceStoreTests")
        store = PersistenceStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "PersistenceStoreTests")
        super.tearDown()
    }

    func testSaveThenLoadRoundTrips() {
        let settings = PersistedSettings(
            action: .lock,
            durationMinutes: 45,
            dailyEnabled: true,
            dailyHour: 22,
            dailyMinute: 15,
            launchAtLogin: true
        )

        store.save(settings)

        XCTAssertEqual(store.load(), settings)
    }

    // Review Focus: first launch with nothing saved yet must return sensible defaults.
    func testLoadWithNoSavedDataReturnsDefaults() {
        XCTAssertEqual(store.load(), PersistedSettings.defaults)
    }
}
