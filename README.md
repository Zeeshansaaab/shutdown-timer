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

