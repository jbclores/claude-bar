import AppKit

@main
enum ClaudeBarMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var state: AppState!
    private var statusItem: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        state = AppState()
        if RenderPeek.runIfRequested(state: state) {
            state.start()
            return
        }
        statusItem = StatusItemController(state: state)
        state.start()
    }
}
