import AppKit
import ServiceManagement

@main
enum ClaudeBarMain {
    @MainActor static func main() {
        // `ClaudeBar --launch-at-login on|off`: same as the dropdown's checkbox, for scripts; prints the result.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--launch-at-login"), i + 1 < args.count {
            do {
                if args[i + 1] == "on" { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                print("launch at login: \(error.localizedDescription)")
            }
            print("launch at login: \(SMAppService.mainApp.status == .enabled ? "on" : "off")")
            exit(SMAppService.mainApp.status == (args[i + 1] == "on" ? .enabled : .notRegistered) ? 0 : 1)
        }
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
            state.sideEffects = false
            if ProcessInfo.processInfo.environment["CLAUDEBAR_NO_DATA"] != "1" { state.start() }
            return
        }
        statusItem = StatusItemController(state: state)
        state.start()
    }
}
