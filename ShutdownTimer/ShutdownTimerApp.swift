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
