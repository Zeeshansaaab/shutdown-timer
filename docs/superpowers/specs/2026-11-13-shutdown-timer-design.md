# Shutdown Timer — Design Spec

Date: 2026-11-13

## Purpose

A native macOS menu bar utility that lets the user trigger a power action
(sleep, shut down, or lock screen) either after a one-off countdown, or on a
recurring daily schedule. Grew out of an earlier plain shell-script sleep
timer; this is the "proper app" version with more triggers, a UI, and a
GitHub release pipeline.

Success criteria:
- Runs as a universal (Intel + Apple Silicon) binary with no dock icon.
- User can start a countdown from quick presets or a custom duration, pick
  the action (sleep / shut down / lock), get a 60s warning notification with
  Cancel/Snooze, and cancel at any time from the menu bar.
- User can set a recurring daily time instead of (or in addition to) a
  one-off countdown.
- App can be configured to launch at login.
- No Apple Developer account required; local builds are ad-hoc signed.
- Pushing a GitHub Release builds and attaches a `.dmg` automatically.

## Approach

Native SwiftUI app (`MenuBarExtra`, macOS 13+ minimum deployment target),
single Xcode project, built headlessly via `xcodebuild`. Chosen over a
hand-assembled SwiftPM `.app` bundle (too much manual packaging/entitlement
work for no benefit) and an Electron-style wrapper (too heavy for an
always-running background utility, worse system API access).

## Architecture

Four internal layers, one SwiftUI app target:

1. **UI layer** — `MenuBarExtra` content: action picker, duration
   presets/custom picker, daily-schedule editor, launch-at-login toggle,
   live countdown label in the menu bar icon itself.
2. **TimerEngine** — single source of truth for timer state (see State
   Machine below); computes remaining time, decides when to post the
   warning notification, and when to fire the configured action.
3. **PowerActions** — thin, protocol-backed wrapper around the three OS
   calls, each invoked through `Process`:
   - Sleep: `pmset sleepnow`
   - Shut down: `osascript -e 'tell application "System Events" to shut down'`
   - Lock screen: `/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession -suspend`
4. **Persistence** — `UserDefaults` for last-used action, last-used
   duration, daily schedule time/enabled flag, and launch-at-login state.

## Components & UI

- **Menu bar icon**: SF Symbol (idle) that swaps to a live `MM:SS` text
  countdown while a timer is running.
- **Dropdown (`MenuBarExtra` menu)**:
  - Action picker — segmented control: Sleep / Shut Down / Lock Screen.
  - Duration — preset buttons (15 / 30 / 60 / 90 min) + custom
    stepper/field for arbitrary minutes.
  - Start / Cancel button — "Start" when idle; "Cancel" + remaining time
    while running.
  - Daily Schedule section — "Enable daily schedule" toggle + time picker.
    Independent of the one-off countdown; if both are somehow relevant, the
    one-off countdown takes priority and the daily schedule just waits for
    its next slot.
  - Launch at Login toggle, backed by `SMAppService`.
  - Quit item.
- **Notification**: ~60s before the action fires, a `UNNotificationRequest`
  — "Shutdown Timer — Mac will <action> in 1 minute" — with **Cancel** and
  **Snooze 10 min** actions, handled via `UNUserNotificationCenterDelegate`.

## State Machine (TimerEngine)

States: `Idle`, `Running(action, fireDate)`, `WarningShown(action, fireDate)`,
`Firing`.

- A repeating 1s timer updates the countdown label from `fireDate - now`.
- At `fireDate - 60s`, transition to `WarningShown` and post the
  notification exactly once (guarded by a flag).
- At `fireDate`, transition to `Firing`, call
  `PowerActions.perform(action)`, then:
  - One-off countdown → return to `Idle`.
  - Daily schedule → recompute `fireDate` as the same time tomorrow and
    return to `Running`.
- **Cancel** (menu or notification action) tears down the active timer,
  returns to `Idle`.
- **Snooze 10 min** (notification action) pushes `fireDate` forward 10
  minutes, returns to `Running`.
- All state changes persist last action/duration/schedule to `UserDefaults`
  immediately.
- On relaunch: a daily schedule (if enabled) re-arms itself automatically;
  a one-off countdown that was running at quit/crash is **not** restored —
  it's simply lost, by design.

## Error Handling & Permissions

- **Shutdown (AppleScript/System Events)**: requires one-time Automation
  permission. On denial/error, catch it, show a notification pointing the
  user to System Settings → Privacy & Security → Automation, and fall back
  to `Idle` instead of silently failing.
- **Lock screen / Sleep**: no special permission needed.
- **Notifications**: permission requested once at first launch. If denied,
  the warning step is silently skipped — the timer still fires on schedule;
  only the heads-up/snooze UX is unavailable (Cancel from the menu bar still
  works).
- **Launch at Login (`SMAppService`)**: registration failures are caught;
  the toggle reverts to its previous state rather than crashing.
- All `Process` calls run with a timeout guard; non-zero exit codes are
  logged via `os.Logger`, never crash the app.

## Testing

- XCTest unit tests for `TimerEngine` transitions (Running → WarningShown →
  Firing, Cancel, Snooze, daily reschedule-to-tomorrow) using an injected
  clock so tests don't depend on real wall-clock sleeps.
- `PowerActions` is protocol-backed so tests inject a fake recorder instead
  of actually sleeping/locking/shutting down the test machine.
- Manual smoke pass after build: short (1-2 min) countdown for each of the
  three actions; notification/snooze/cancel flow; daily schedule re-arm
  after relaunch; launch-at-login toggle actually adds/removes the login
  item.

## Build & Local Distribution

- Xcode project at `~/Projects/Learning/ShutdownTimer`, scheme
  `ShutdownTimer`, `ARCHS = arm64 x86_64`, `ONLY_ACTIVE_ARCH = NO`.
- Built headlessly: `xcodebuild -scheme ShutdownTimer -configuration Release build`.
- Resulting `.app` ad-hoc codesigned: `codesign --force --deep --sign -`.
- Copied to `/Applications`; verified universal via `lipo -info` on the
  binary (expect both `x86_64` and `arm64` slices).
- No paid Apple Developer account/signing involved.

## CI/CD — GitHub Actions DMG Release

- `.github/workflows/release.yml`, trigger: `on: release: types: [published]`
  (fires when a release is published on GitHub, not on draft creation).
- Runner: `macos-latest` (cross-compiles both architectures regardless of
  its own CPU).
- Steps: checkout → `xcodebuild` Release build (same universal settings) →
  ad-hoc codesign the `.app` → stage into a folder → `hdiutil create
  -volname "Shutdown Timer" -srcfolder <staging> -ov -format UDZO
  ShutdownTimer.dmg` → upload `ShutdownTimer.dmg` as a release asset via
  `softprops/action-gh-release` using the built-in `GITHUB_TOKEN` (job needs
  `permissions: contents: write`).
- No Developer ID signing in CI either — downloaders see the same one-time
  Gatekeeper right-click-to-open prompt as a local build.
- `gh` CLI is not installed/authenticated locally, so the user creates the
  GitHub repo and pushes manually.

## Out of Scope (explicitly not building)

- Restart, log out, and "prevent sleep" (caffeinate) actions — considered,
  not selected.
- App Store distribution / paid Developer ID signing.
- True background scheduling via `launchd`/LaunchAgent — the daily schedule
  only fires while the app process is running (acceptable given
  launch-at-login keeps it running most of the time).
