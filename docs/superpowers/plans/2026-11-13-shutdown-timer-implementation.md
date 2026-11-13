# Shutdown Timer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS menu bar app ("Shutdown Timer") that sleeps, shuts down, or locks the Mac after a one-off countdown or a recurring daily schedule, plus a GitHub Actions workflow that builds and attaches a DMG whenever a GitHub Release is published.

**Architecture:** Single SwiftUI app target (`MenuBarExtra`, no dock icon) split into four layers — UI, a `TimerEngine` state machine, a `PowerActions` wrapper around `Process` calls, and `UserDefaults`-backed persistence — generated via `xcodegen` and built headlessly with `xcodebuild` as a universal (arm64 + x86_64) binary.

**Tech Stack:** Swift 5 / SwiftUI, XCTest, `xcodegen`, `xcodebuild`, GitHub Actions (`macos-latest`), `hdiutil`, `softprops/action-gh-release`.

**Spec:** `docs/superpowers/specs/2026-11-13-shutdown-timer-design.md`

## Global Constraints

- Minimum deployment target: macOS 13.0 (required by `MenuBarExtra` and `SMAppService`).
- Universal binary: `ARCHS = arm64 x86_64`, `ONLY_ACTIVE_ARCH = NO` on every build (local and CI).
- No dock icon: `LSUIElement = true`.
- No sandbox entitlements, no paid Apple Developer ID. Local and CI builds are ad-hoc codesigned via `codesign --force --deep --sign -`.
- Power actions are invoked only via these exact `Process` calls: sleep → `/usr/bin/pmset sleepnow`; shut down → `/usr/bin/osascript -e 'tell application "System Events" to shut down'`; lock → `/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession -suspend`.
- Settings persist as a single `Codable` JSON blob in `UserDefaults`.
- The daily schedule only fires while the app process is running — no `launchd`/LaunchAgent integration (out of scope per spec).
- GitHub Actions workflow trigger: `on: release: types: [published]`; runner `macos-latest`; DMG built with `hdiutil`; uploaded via `softprops/action-gh-release` using the built-in `GITHUB_TOKEN` with `permissions: contents: write`.
- All local/CI build commands use `-derivedDataPath build` so the built `.app` always lands at a predictable path: `build/Build/Products/<Config>/ShutdownTimer.app`.

## Review Focus

- Out-of-range custom duration (zero, negative, or >24h) must be clamped to a sane range, never start a zero-length or multi-day timer — tested in Task 3.
- `snooze()` called when the engine is **not** in `warningShown` (e.g. idle) must be a no-op, not an unexpected state jump — tested in Task 3.
- `cancel()` called while already idle must stay idle, not crash or misbehave — tested in Task 3.
- A daily-schedule target time exactly equal to "now" must resolve to **tomorrow**, not fire again immediately — tested in Task 4.
- First launch with nothing in `UserDefaults` yet must return documented defaults, not crash on a nil/decode failure — tested in Task 5.

---

## Task 1: Project Scaffolding

**Files:**
- Create: `project.yml`
- Create: `.gitignore`
- Create: `ShutdownTimer/ShutdownTimerApp.swift`
- Create: `ShutdownTimerTests/PlaceholderTests.swift`
- Generate: `ShutdownTimer.xcodeproj` (via `xcodegen`)
- Generate: `ShutdownTimer/Info.plist` (via `xcodegen`)

**Interfaces:**
- Consumes: nothing (first task).
- Produces: a buildable, testable Xcode project named `ShutdownTimer` with targets `ShutdownTimer` (app) and `ShutdownTimerTests` (unit tests), both building for `arm64` and `x86_64`. Every later task adds files under `ShutdownTimer/` or `ShutdownTimerTests/` and re-runs `xcodegen generate`.

- [ ] **Step 1: Install xcodegen**

```bash
brew install xcodegen
xcodegen --version
```

Expected: prints a version number (e.g. `2.x.x`).

- [ ] **Step 2: Create source directories**

```bash
cd ~/Projects/Learning/ShutdownTimer
mkdir -p ShutdownTimer ShutdownTimerTests
```

- [ ] **Step 3: Write `project.yml`**

```yaml
name: ShutdownTimer
options:
  bundleIdPrefix: com.zeeshan
targets:
  ShutdownTimer:
    type: application
    platform: macOS
    deploymentTarget: "13.0"
    sources:
      - path: ShutdownTimer
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.zeeshan.ShutdownTimer
        ARCHS: "arm64 x86_64"
        ONLY_ACTIVE_ARCH: NO
        CODE_SIGN_IDENTITY: ""
        CODE_SIGNING_REQUIRED: NO
        CODE_SIGNING_ALLOWED: NO
        MARKETING_VERSION: "1.0"
        CURRENT_PROJECT_VERSION: "1"
        SWIFT_VERSION: "5"
    info:
      path: ShutdownTimer/Info.plist
      properties:
        LSUIElement: true
        NSAppleEventsUsageDescription: "Shutdown Timer needs permission to control System Events in order to shut down your Mac."
  ShutdownTimerTests:
    type: bundle.unit-test
    platform: macOS
    deploymentTarget: "13.0"
    sources:
      - path: ShutdownTimerTests
    settings:
      base:
        ARCHS: "arm64 x86_64"
        ONLY_ACTIVE_ARCH: NO
        SWIFT_VERSION: "5"
    dependencies:
      - target: ShutdownTimer
schemes:
  ShutdownTimer:
    build:
      targets:
        ShutdownTimer: all
        ShutdownTimerTests: [test]
    test:
      targets:
        - ShutdownTimerTests
```

- [ ] **Step 4: Write the minimal app shell**

`ShutdownTimer/ShutdownTimerApp.swift`:

```swift
import SwiftUI

@main
struct ShutdownTimerApp: App {
    var body: some Scene {
        MenuBarExtra("Shutdown Timer", systemImage: "moon.zzz") {
            Text("Shutdown Timer")
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 5: Write a placeholder test so the test target has a source file**

`ShutdownTimerTests/PlaceholderTests.swift`:

```swift
import XCTest

final class PlaceholderTests: XCTestCase {
    func testTrue() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 6: Write `.gitignore`**

```
.DS_Store
build/
DerivedData/
*.xcuserstate
xcuserdata/
.swiftpm/
*.dmg
dmg-staging/
```

- [ ] **Step 7: Generate the Xcode project**

```bash
cd ~/Projects/Learning/ShutdownTimer
xcodegen generate
```

Expected: `Created project at ShutdownTimer.xcodeproj` and the file exists.

- [ ] **Step 8: Build the app**

```bash
xcodebuild -project ShutdownTimer.xcodeproj -scheme ShutdownTimer \
  -configuration Debug -derivedDataPath build build
```

Expected: ends with `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Verify the binary is universal**

```bash
lipo -info build/Build/Products/Debug/ShutdownTimer.app/Contents/MacOS/ShutdownTimer
```

Expected: `Architectures in the fat file: ... are: x86_64 arm64`.

- [ ] **Step 10: Run the test target**

```bash
xcodebuild test -project ShutdownTimer.xcodeproj -scheme ShutdownTimer \
  -destination 'platform=macOS' -derivedDataPath build
```

Expected: `Test Suite 'All tests' passed` with `PlaceholderTests.testTrue` passing.

- [ ] **Step 11: Commit**

```bash
git add project.yml .gitignore ShutdownTimer.xcodeproj ShutdownTimer/ShutdownTimerApp.swift \
  ShutdownTimer/Info.plist ShutdownTimerTests/PlaceholderTests.swift
git commit -m "Scaffold ShutdownTimer Xcode project via xcodegen"
```

---

## Task 2: PowerAction & PowerActions

**Files:**
- Create: `ShutdownTimer/PowerActions.swift`
- Test: `ShutdownTimerTests/PowerActionsTests.swift`
- Create: `ShutdownTimerTests/FakePowerActions.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `enum PowerAction: String, CaseIterable, Codable, Identifiable { case sleep, shutDown, lock }` with `var displayName: String`; `protocol PowerActionsExecuting { func perform(_ action: PowerAction) throws }`; `struct LaunchCommand: Equatable { let launchPath: String; let arguments: [String] }`; `struct PowerActions: PowerActionsExecuting` with `static func command(for action: PowerAction) -> LaunchCommand`; `final class FakePowerActions: PowerActionsExecuting` with `private(set) var performedActions: [PowerAction]` and `var errorToThrow: Error?`. Later tasks (3, 8, 9) depend on all of these exact names.

- [ ] **Step 1: Write the failing test**

`ShutdownTimerTests/PowerActionsTests.swift`:

```swift
import XCTest
@testable import ShutdownTimer

final class PowerActionsTests: XCTestCase {
    func testSleepCommand() {
        let command = PowerActions.command(for: .sleep)
        XCTAssertEqual(command, LaunchCommand(launchPath: "/usr/bin/pmset", arguments: ["sleepnow"]))
    }

    func testShutDownCommand() {
        let command = PowerActions.command(for: .shutDown)
        XCTAssertEqual(
            command,
            LaunchCommand(
                launchPath: "/usr/bin/osascript",
                arguments: ["-e", "tell application \"System Events\" to shut down"]
            )
        )
    }

    func testLockCommand() {
        let command = PowerActions.command(for: .lock)
        XCTAssertEqual(
            command,
            LaunchCommand(
                launchPath: "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession",
                arguments: ["-suspend"]
            )
        )
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
xcodebuild test -project ShutdownTimer.xcodeproj -scheme ShutdownTimer \
  -destination 'platform=macOS' -derivedDataPath build
```

Expected: FAIL — `PowerActions`/`LaunchCommand` not defined.

- [ ] **Step 3: Implement `PowerActions.swift`**

`ShutdownTimer/PowerActions.swift`:

```swift
import Foundation

enum PowerAction: String, CaseIterable, Codable, Identifiable {
    case sleep
    case shutDown
    case lock

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sleep: return "Sleep"
        case .shutDown: return "Shut Down"
        case .lock: return "Lock Screen"
        }
    }
}

protocol PowerActionsExecuting {
    func perform(_ action: PowerAction) throws
}

struct LaunchCommand: Equatable {
    let launchPath: String
    let arguments: [String]
}

struct PowerActions: PowerActionsExecuting {
    static func command(for action: PowerAction) -> LaunchCommand {
        switch action {
        case .sleep:
            return LaunchCommand(launchPath: "/usr/bin/pmset", arguments: ["sleepnow"])
        case .shutDown:
            return LaunchCommand(
                launchPath: "/usr/bin/osascript",
                arguments: ["-e", "tell application \"System Events\" to shut down"]
            )
        case .lock:
            return LaunchCommand(
                launchPath: "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession",
                arguments: ["-suspend"]
            )
        }
    }

    func perform(_ action: PowerAction) throws {
        let command = PowerActions.command(for: action)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.launchPath)
        process.arguments = command.arguments
        try process.run()
        process.waitUntilExit()
    }
}
```

- [ ] **Step 4: Add the test fake used by later tasks**

`ShutdownTimerTests/FakePowerActions.swift`:

```swift
import Foundation
@testable import ShutdownTimer

final class FakePowerActions: PowerActionsExecuting {
    private(set) var performedActions: [PowerAction] = []
    var errorToThrow: Error?

    func perform(_ action: PowerAction) throws {
        if let error = errorToThrow {
            throw error
        }
        performedActions.append(action)
    }
}
```

- [ ] **Step 5: Regenerate the project and run tests**

```bash
xcodegen generate
xcodebuild test -project ShutdownTimer.xcodeproj -scheme ShutdownTimer \
  -destination 'platform=macOS' -derivedDataPath build
```

Expected: PASS — all `PowerActionsTests` pass.

- [ ] **Step 6: Commit**

```bash
git add ShutdownTimer.xcodeproj ShutdownTimer/PowerActions.swift \
  ShutdownTimerTests/PowerActionsTests.swift ShutdownTimerTests/FakePowerActions.swift
git commit -m "Add PowerAction/PowerActions command builder"
```

---

## Task 3: TimerEngine core state machine

**Files:**
- Create: `ShutdownTimer/TimerEngine.swift`
- Create: `ShutdownTimerTests/FakeTimerNotifying.swift`
- Test: `ShutdownTimerTests/TimerEngineTests.swift`

**Interfaces:**
- Consumes: `PowerAction`, `PowerActionsExecuting`, `FakePowerActions` (Task 2).
- Produces: `enum TimerState: Equatable { case idle; case running(action: PowerAction, fireDate: Date, isDaily: Bool); case warningShown(action: PowerAction, fireDate: Date, isDaily: Bool) }`; `protocol TimerNotifying { func postWarning(for action: PowerAction); func postPermissionError(for action: PowerAction) }`; `final class TimerEngine: ObservableObject` with `@Published private(set) var state: TimerState`, `static let warningLeadTime/minimumDuration/maximumDuration: TimeInterval`, `init(powerActions:notifier:clock:)`, `func start(action:duration:isDaily:)`, `func startAt(action:fireDate:isDaily:)`, `func cancel()`, `func snooze(by:)`, `func tick()`. Tasks 4, 6→8 (via `SettingsViewModel`), and 9 depend on these exact names.

- [ ] **Step 1: Write the failing tests**

`ShutdownTimerTests/FakeTimerNotifying.swift`:

```swift
import Foundation
@testable import ShutdownTimer

final class FakeTimerNotifying: TimerNotifying {
    private(set) var warningCount = 0
    private(set) var permissionErrorCount = 0

    func postWarning(for action: PowerAction) {
        warningCount += 1
    }

    func postPermissionError(for action: PowerAction) {
        permissionErrorCount += 1
    }
}
```

`ShutdownTimerTests/TimerEngineTests.swift`:

```swift
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
```

- [ ] **Step 2: Run to verify it fails**

```bash
xcodebuild test -project ShutdownTimer.xcodeproj -scheme ShutdownTimer \
  -destination 'platform=macOS' -derivedDataPath build
```

Expected: FAIL — `TimerState`/`TimerNotifying`/`TimerEngine` not defined.

- [ ] **Step 3: Implement `TimerEngine.swift`**

`ShutdownTimer/TimerEngine.swift`:

```swift
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
```

- [ ] **Step 4: Regenerate the project and run tests**

```bash
xcodegen generate
xcodebuild test -project ShutdownTimer.xcodeproj -scheme ShutdownTimer \
  -destination 'platform=macOS' -derivedDataPath build
```

Expected: PASS — all `TimerEngineTests` pass.

- [ ] **Step 5: Commit**

```bash
git add ShutdownTimer.xcodeproj ShutdownTimer/TimerEngine.swift \
  ShutdownTimerTests/FakeTimerNotifying.swift ShutdownTimerTests/TimerEngineTests.swift
git commit -m "Add TimerEngine state machine with warning/snooze/daily-fire logic"
```

---

## Task 4: DailySchedule + TimerEngine.startDaily

**Files:**
- Create: `ShutdownTimer/DailySchedule.swift`
- Modify: `ShutdownTimer/TimerEngine.swift` (add `startDaily` extension)
- Test: `ShutdownTimerTests/DailyScheduleTests.swift`

**Interfaces:**
- Consumes: `TimerEngine.startAt(action:fireDate:isDaily:)` and `TimerEngine.clock` (Task 3).
- Produces: `struct DailySchedule { static func nextFireDate(hour: Int, minute: Int, after date: Date, calendar: Calendar = .current) -> Date }`; `extension TimerEngine { func startDaily(action: PowerAction, hour: Int, minute: Int) }`. Task 8's `SettingsViewModel` depends on `startDaily`.

- [ ] **Step 1: Write the failing tests**

`ShutdownTimerTests/DailyScheduleTests.swift`:

```swift
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
```

- [ ] **Step 2: Run to verify it fails**

```bash
xcodebuild test -project ShutdownTimer.xcodeproj -scheme ShutdownTimer \
  -destination 'platform=macOS' -derivedDataPath build
```

Expected: FAIL — `DailySchedule`/`startDaily` not defined.

- [ ] **Step 3: Implement `DailySchedule.swift`**

`ShutdownTimer/DailySchedule.swift`:

```swift
import Foundation

struct DailySchedule {
    static func nextFireDate(hour: Int, minute: Int, after date: Date, calendar: Calendar = .current) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = minute
        components.second = 0

        guard let candidate = calendar.date(from: components) else {
            return date
        }

        if candidate > date {
            return candidate
        }

        return calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
    }
}
```

- [ ] **Step 4: Add `startDaily` to `TimerEngine`**

Append to `ShutdownTimer/TimerEngine.swift`:

```swift
extension TimerEngine {
    func startDaily(action: PowerAction, hour: Int, minute: Int) {
        let fireDate = DailySchedule.nextFireDate(hour: hour, minute: minute, after: clock())
        startAt(action: action, fireDate: fireDate, isDaily: true)
    }
}
```

- [ ] **Step 5: Regenerate the project and run tests**

```bash
xcodegen generate
xcodebuild test -project ShutdownTimer.xcodeproj -scheme ShutdownTimer \
  -destination 'platform=macOS' -derivedDataPath build
```

Expected: PASS — all `DailyScheduleTests` pass, plus all prior tests still pass.

- [ ] **Step 6: Commit**

```bash
git add ShutdownTimer.xcodeproj ShutdownTimer/DailySchedule.swift ShutdownTimer/TimerEngine.swift \
  ShutdownTimerTests/DailyScheduleTests.swift
git commit -m "Add DailySchedule.nextFireDate and TimerEngine.startDaily"
```

---

## Task 5: PersistenceStore

**Files:**
- Create: `ShutdownTimer/PersistenceStore.swift`
- Test: `ShutdownTimerTests/PersistenceStoreTests.swift`

**Interfaces:**
- Consumes: `PowerAction` (Task 2).
- Produces: `struct PersistedSettings: Codable, Equatable { var action: PowerAction; var durationMinutes: Int; var dailyEnabled: Bool; var dailyHour: Int; var dailyMinute: Int; var launchAtLogin: Bool; static let defaults: PersistedSettings }`; `final class PersistenceStore { init(defaults: UserDefaults = .standard); func load() -> PersistedSettings; func save(_ settings: PersistedSettings) }`. Task 8's `SettingsViewModel` depends on these exact names.

- [ ] **Step 1: Write the failing tests**

`ShutdownTimerTests/PersistenceStoreTests.swift`:

```swift
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
```

- [ ] **Step 2: Run to verify it fails**

```bash
xcodebuild test -project ShutdownTimer.xcodeproj -scheme ShutdownTimer \
  -destination 'platform=macOS' -derivedDataPath build
```

Expected: FAIL — `PersistedSettings`/`PersistenceStore` not defined.

- [ ] **Step 3: Implement `PersistenceStore.swift`**

`ShutdownTimer/PersistenceStore.swift`:

```swift
import Foundation

struct PersistedSettings: Codable, Equatable {
    var action: PowerAction
    var durationMinutes: Int
    var dailyEnabled: Bool
    var dailyHour: Int
    var dailyMinute: Int
    var launchAtLogin: Bool

    static let defaults = PersistedSettings(
        action: .sleep,
        durationMinutes: 15,
        dailyEnabled: false,
        dailyHour: 23,
        dailyMinute: 0,
        launchAtLogin: false
    )
}

final class PersistenceStore {
    private let defaults: UserDefaults
    private let key = "com.zeeshan.ShutdownTimer.settings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> PersistedSettings {
        guard
            let data = defaults.data(forKey: key),
            let settings = try? JSONDecoder().decode(PersistedSettings.self, from: data)
        else {
            return .defaults
        }
        return settings
    }

    func save(_ settings: PersistedSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
```

- [ ] **Step 4: Regenerate the project and run tests**

```bash
xcodegen generate
xcodebuild test -project ShutdownTimer.xcodeproj -scheme ShutdownTimer \
  -destination 'platform=macOS' -derivedDataPath build
```

Expected: PASS — all `PersistenceStoreTests` pass, plus all prior tests still pass.

- [ ] **Step 5: Commit**

```bash
git add ShutdownTimer.xcodeproj ShutdownTimer/PersistenceStore.swift \
  ShutdownTimerTests/PersistenceStoreTests.swift
git commit -m "Add PersistenceStore for UserDefaults-backed settings"
```

---

## Task 6: LoginItemManager

**Files:**
- Create: `ShutdownTimer/LoginItemManager.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `final class LoginItemManager { var isEnabled: Bool { get }; func setEnabled(_ enabled: Bool) }`. Task 8's `SettingsViewModel` and Task 9's app wiring depend on this.

This wraps `SMAppService`, which only behaves correctly for an app actually installed in `/Applications` and registered with Launch Services — it cannot be meaningfully unit tested in isolation, so this task is build-verified plus a manual check.

- [ ] **Step 1: Implement `LoginItemManager.swift`**

`ShutdownTimer/LoginItemManager.swift`:

```swift
import ServiceManagement
import os

final class LoginItemManager {
    private let logger = Logger(subsystem: "com.zeeshan.ShutdownTimer", category: "LoginItemManager")

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Failed to \(enabled ? "register" : "unregister") login item: \(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 2: Regenerate the project and build**

```bash
xcodegen generate
xcodebuild -project ShutdownTimer.xcodeproj -scheme ShutdownTimer \
  -configuration Debug -derivedDataPath build build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ShutdownTimer.xcodeproj ShutdownTimer/LoginItemManager.swift
git commit -m "Add LoginItemManager wrapping SMAppService"
```

*(Manual verification of the actual login-item toggle happens in Task 9's smoke test, once the app is copied to `/Applications` and wired to a UI control.)*

---

## Task 7: NotificationManager

**Files:**
- Create: `ShutdownTimer/NotificationManager.swift`

**Interfaces:**
- Consumes: `PowerAction` (Task 2), `TimerNotifying` (Task 3).
- Produces: `final class NotificationManager: NSObject, TimerNotifying, UNUserNotificationCenterDelegate` with `var onCancel: (() -> Void)?`, `var onSnooze: (() -> Void)?`, `func requestAuthorization()`. Task 9's app wiring depends on this.

`UNUserNotificationCenter` requires a running, foreground-approved app to test interactively, so this task is build-verified plus a manual check in Task 9.

- [ ] **Step 1: Implement `NotificationManager.swift`**

`ShutdownTimer/NotificationManager.swift`:

```swift
import UserNotifications

final class NotificationManager: NSObject, TimerNotifying, UNUserNotificationCenterDelegate {
    static let categoryIdentifier = "com.zeeshan.ShutdownTimer.warning"
    static let cancelActionIdentifier = "com.zeeshan.ShutdownTimer.cancel"
    static let snoozeActionIdentifier = "com.zeeshan.ShutdownTimer.snooze"

    var onCancel: (() -> Void)?
    var onSnooze: (() -> Void)?

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
        registerCategory()
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func postWarning(for action: PowerAction) {
        let content = UNMutableNotificationContent()
        content.title = "Shutdown Timer"
        content.body = "Mac will \(action.displayName.lowercased()) in 1 minute."
        content.categoryIdentifier = Self.categoryIdentifier

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }

    func postPermissionError(for action: PowerAction) {
        let content = UNMutableNotificationContent()
        content.title = "Shutdown Timer"
        content.body = "Couldn't \(action.displayName.lowercased()) your Mac. Check System Settings > Privacy & Security > Automation."
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }

    private func registerCategory() {
        let cancelAction = UNNotificationAction(identifier: Self.cancelActionIdentifier, title: "Cancel", options: [])
        let snoozeAction = UNNotificationAction(identifier: Self.snoozeActionIdentifier, title: "Snooze 10 min", options: [])
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [cancelAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        switch response.actionIdentifier {
        case Self.cancelActionIdentifier:
            onCancel?()
        case Self.snoozeActionIdentifier:
            onSnooze?()
        default:
            break
        }
        completionHandler()
    }
}
```

- [ ] **Step 2: Regenerate the project and build**

```bash
xcodegen generate
xcodebuild -project ShutdownTimer.xcodeproj -scheme ShutdownTimer \
  -configuration Debug -derivedDataPath build build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ShutdownTimer.xcodeproj ShutdownTimer/NotificationManager.swift
git commit -m "Add NotificationManager wrapping UNUserNotificationCenter"
```

---

## Task 8: SettingsViewModel + MenuBarContentView

**Files:**
- Create: `ShutdownTimer/SettingsViewModel.swift`
- Create: `ShutdownTimer/MenuBarContentView.swift`

**Interfaces:**
- Consumes: `PowerAction`, `TimerEngine`, `TimerState`, `TimerEngine.startDaily`, `PersistenceStore`, `PersistedSettings`, `LoginItemManager` (Tasks 2–6).
- Produces: `final class SettingsViewModel: ObservableObject` with published `action/durationMinutes/dailyEnabled/dailyTime/launchAtLogin`, `init(store:loginItemManager:)`, `func attach(engine: TimerEngine)`, `func startTimer(using engine: TimerEngine)`; `struct MenuBarContentView: View` taking `engine: TimerEngine` and `settingsStore: SettingsViewModel`. Task 9 depends on both.

- [ ] **Step 1: Implement `SettingsViewModel.swift`**

`ShutdownTimer/SettingsViewModel.swift`:

```swift
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
```

- [ ] **Step 2: Implement `MenuBarContentView.swift`**

`ShutdownTimer/MenuBarContentView.swift`:

```swift
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

            HStack {
                ForEach(presets, id: \.self) { minutes in
                    Button("\(minutes)m") {
                        settingsStore.durationMinutes = minutes
                    }
                }
                Stepper("\(settingsStore.durationMinutes) min", value: $settingsStore.durationMinutes, in: 1...1440)
            }

            startCancelButton

            Divider()

            Toggle("Enable daily schedule", isOn: $settingsStore.dailyEnabled)
            if settingsStore.dailyEnabled {
                DatePicker("Daily time", selection: $settingsStore.dailyTime, displayedComponents: .hourAndMinute)
            }

            Divider()

            Toggle("Launch at Login", isOn: $settingsStore.launchAtLogin)

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 260)
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
```

- [ ] **Step 3: Regenerate the project and build**

```bash
xcodegen generate
xcodebuild -project ShutdownTimer.xcodeproj -scheme ShutdownTimer \
  -configuration Debug -derivedDataPath build build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run the full test suite to confirm no regressions**

```bash
xcodebuild test -project ShutdownTimer.xcodeproj -scheme ShutdownTimer \
  -destination 'platform=macOS' -derivedDataPath build
```

Expected: all existing tests still pass (this task adds UI/view-model plumbing with no new unit tests of its own — it's covered transitively by `TimerEngine`/`PersistenceStore` tests plus the Task 9 manual smoke test).

- [ ] **Step 5: Commit**

```bash
git add ShutdownTimer.xcodeproj ShutdownTimer/SettingsViewModel.swift ShutdownTimer/MenuBarContentView.swift
git commit -m "Add SettingsViewModel and MenuBarContentView UI"
```

---

## Task 9: Wire up ShutdownTimerApp + menu bar countdown label

**Files:**
- Modify: `ShutdownTimer/ShutdownTimerApp.swift` (replace Task 1's placeholder)

**Interfaces:**
- Consumes: everything from Tasks 2–8.
- Produces: the finished, runnable app. No later task depends on this.

- [ ] **Step 1: Replace `ShutdownTimerApp.swift` with the full wiring**

`ShutdownTimer/ShutdownTimerApp.swift`:

```swift
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

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            switch engine.state {
            case .idle:
                Image(systemName: "moon.zzz")
            case .running(_, let fireDate, _), .warningShown(_, let fireDate, _):
                Text(countdownText(until: fireDate))
            }
        }
        .onReceive(ticker) { tick in
            now = tick
            engine.tick()
        }
    }

    private func countdownText(until fireDate: Date) -> String {
        let remaining = max(0, Int(fireDate.timeIntervalSince(now)))
        return String(format: "%02d:%02d", remaining / 60, remaining % 60)
    }
}
```

- [ ] **Step 2: Regenerate the project and build**

```bash
xcodegen generate
xcodebuild -project ShutdownTimer.xcodeproj -scheme ShutdownTimer \
  -configuration Release -derivedDataPath build build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run the full test suite**

```bash
xcodebuild test -project ShutdownTimer.xcodeproj -scheme ShutdownTimer \
  -destination 'platform=macOS' -derivedDataPath build
```

Expected: every test from Tasks 2–5 still passes.

- [ ] **Step 4: Ad-hoc codesign and install**

```bash
codesign --force --deep --sign - build/Build/Products/Release/ShutdownTimer.app
lipo -info build/Build/Products/Release/ShutdownTimer.app/Contents/MacOS/ShutdownTimer
cp -R build/Build/Products/Release/ShutdownTimer.app /Applications/
```

Expected: `lipo -info` reports both `x86_64` and `arm64`.

- [ ] **Step 5: Manual smoke test**

1. Launch `/Applications/ShutdownTimer.app`. Confirm a menu bar icon appears (no dock icon).
2. Click it, pick **Lock Screen**, set a 1-minute custom duration, click **Start**. Confirm the icon shows a `00:59`-style countdown.
3. After ~59 seconds, confirm a notification appears with **Cancel** and **Snooze 10 min** actions; click **Snooze 10 min** and confirm the countdown jumps forward 10 minutes.
4. Start a fresh 1-minute **Lock Screen** timer, let it run to completion, confirm the screen locks.
5. Enable **Daily Schedule** for a time ~2 minutes out, quit the app (not just lock), relaunch it from `/Applications`, confirm the countdown is still armed for that same time without having to reconfigure it.
6. Toggle **Launch at Login** on, check System Settings → General → Login Items & Extensions to confirm it's listed; toggle off and confirm it's removed.
7. Only when you're actually ready to stop for the session: start a short **Shut Down** timer. The first time, macOS will prompt for Automation permission to control "System Events" — approve it, and confirm the Mac shuts down when the timer completes.

- [ ] **Step 6: Commit**

```bash
git add ShutdownTimer.xcodeproj ShutdownTimer/ShutdownTimerApp.swift
git commit -m "Wire up ShutdownTimerApp: menu bar countdown, notifications, login item"
```

---

## Task 10: GitHub Actions release workflow + README

**Files:**
- Create: `.github/workflows/release.yml`
- Create: `README.md`

**Interfaces:**
- Consumes: the Xcode project/scheme from Task 1.
- Produces: a CI workflow that builds and attaches `ShutdownTimer.dmg` to a published GitHub Release. No later task depends on this.

- [ ] **Step 1: Write the workflow**

`.github/workflows/release.yml`:

```yaml
name: Release

on:
  release:
    types: [published]

permissions:
  contents: write

jobs:
  build-dmg:
    runs-on: macos-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Build universal app
        run: |
          xcodebuild -project ShutdownTimer.xcodeproj \
            -scheme ShutdownTimer \
            -configuration Release \
            -derivedDataPath build \
            build

      - name: Ad-hoc codesign
        run: |
          codesign --force --deep --sign - "build/Build/Products/Release/ShutdownTimer.app"

      - name: Verify universal binary
        run: |
          lipo -info "build/Build/Products/Release/ShutdownTimer.app/Contents/MacOS/ShutdownTimer"

      - name: Create DMG
        run: |
          mkdir -p dmg-staging
          cp -R "build/Build/Products/Release/ShutdownTimer.app" dmg-staging/
          hdiutil create -volname "Shutdown Timer" -srcfolder dmg-staging -ov -format UDZO ShutdownTimer.dmg

      - name: Upload DMG to release
        uses: softprops/action-gh-release@v2
        with:
          files: ShutdownTimer.dmg
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

- [ ] **Step 2: Validate the YAML syntax**

```bash
ruby -ryaml -e "YAML.load_file('.github/workflows/release.yml'); puts 'valid'"
```

Expected: prints `valid`.

- [ ] **Step 3: Write `README.md`**

`README.md`:

```markdown
# Shutdown Timer

A macOS menu bar app that sleeps, shuts down, or locks your Mac after a
countdown or on a recurring daily schedule. Universal binary (Apple
Silicon + Intel), no App Store, no paid Developer ID.

## Build locally

    brew install xcodegen   # first time only
    xcodegen generate
    xcodebuild -project ShutdownTimer.xcodeproj -scheme ShutdownTimer \
      -configuration Release -derivedDataPath build build
    codesign --force --deep --sign - build/Build/Products/Release/ShutdownTimer.app
    cp -R build/Build/Products/Release/ShutdownTimer.app /Applications/

First launch: right-click the app in `/Applications` → **Open** (Gatekeeper
will otherwise block an unsigned app). The Shut Down action will prompt
once for Automation permission to control "System Events" — approve it in
System Settings → Privacy & Security → Automation.

## Run tests

    xcodebuild test -project ShutdownTimer.xcodeproj -scheme ShutdownTimer \
      -destination 'platform=macOS' -derivedDataPath build

## Push to GitHub and cut a release (builds+attaches a DMG automatically)

    git remote add origin <your-repo-url>
    git push -u origin main

Then, on github.com: **Releases → Draft a new release**, pick a tag, and
click **Publish release**. The `release.yml` workflow builds a universal
`ShutdownTimer.dmg` and attaches it to that release automatically — no
local `gh` CLI needed.
```

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/release.yml README.md
git commit -m "Add GitHub Actions DMG release workflow and README"
```

---
