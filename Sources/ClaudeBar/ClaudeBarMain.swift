import AppKit
import ServiceManagement
import ClaudeBarCore

@main
enum ClaudeBarMain {
    @MainActor static func main() {
        // `ClaudeBar --launch-at-login on|off`: same as the dropdown's checkbox, for scripts; prints the result.
        let args = CommandLine.arguments
        // `ClaudeBar --undo [--remove]`: undo ClaudeBar's changes from Terminal (see UndoCommand).
        if args.contains("--undo") { UndoCommand.run(remove: args.contains("--remove")) }
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
        // One ClaudeBar at a time: a second copy (say the build folder's, also opened at login) quits before it
        // starts anything, leaving the one already in the menu bar. Renders and click tests run beside it.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .map(\.processIdentifier)
        if SingleInstance.shouldQuit(arguments: CommandLine.arguments, me: getpid(), running: others) {
            NSApp.terminate(nil)
            return
        }
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
