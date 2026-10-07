import AppKit
import ClaudeBarCore
import SwiftUI

/// The onboarding window: opens by itself on first launch, and from the Office card and Settings.
@MainActor
final class SetupWindow {
    static let shared = SetupWindow()
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?
    /// Opens the dropdown ("Open the office"); set by the menu bar item.
    var openDropdown: (() -> Void)?

    func open(state: AppState, env: SetupEnvironment = .real) {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let model = SetupModel(state: state, env: env)
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: SetupView.size), styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = "Set up ClaudeBar"
        w.isReleasedWhenClosed = false
        // Stays open while the user switches apps (ClaudeBar is an accessory app).
        w.hidesOnDeactivate = false
        w.contentView = NSHostingView(rootView: SetupView(model: model).environmentObject(state))
        w.center()
        model.onClose = { [weak self] in self?.window?.close() }
        model.onOpenOffice = { [weak self] in self?.openDropdown?() }
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // Closing with the red button counts as skipping.
                if !state.settings.setup.seen { state.setSetup(SetupSettings(seen: true, state: nil)) }
                self?.window = nil
                if let token = self?.closeObserver { NotificationCenter.default.removeObserver(token) }
                self?.closeObserver = nil
            }
        }
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
