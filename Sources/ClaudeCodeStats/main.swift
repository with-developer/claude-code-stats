import AppKit

// Use @MainActor to satisfy Swift concurrency requirements
@MainActor
func runApp() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate

    // Hide from Dock (menu bar only app)
    app.setActivationPolicy(.accessory)

    app.run()
}

// MainActor.assumeIsolated is needed since top-level code runs on main thread
MainActor.assumeIsolated {
    runApp()
}
