import AppKit
import ClaudeBarCore
import Combine
import SwiftUI

/// The onboarding window: opens by itself on first launch, and from the Office card and Settings.
@MainActor
final class SetupWindow {
    static let shared = SetupWindow()
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?
    private var delegate: SetupWindowDelegate?
    private var workingWatch: AnyCancellable?
    /// The open window's model (the click test drives it; nil while closed).
    private(set) var model: SetupModel?
    /// Opens the dropdown ("Open the office"); set by the menu bar item.
    var openDropdown: (() -> Void)?

    /// `offscreen`: the click test's window, far off any screen and without activating the app.
    func open(state: AppState, env: SetupEnvironment = .real, offscreen: Bool = false) {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let model = SetupModel(state: state, env: env)
        self.model = model
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: SetupView.size), styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = "Set up ClaudeBar"
        w.isReleasedWhenClosed = false
        // Stays open while the user switches apps (ClaudeBar is an accessory app).
        w.hidesOnDeactivate = false
        w.contentView = NSHostingView(rootView: SetupView(model: model).environmentObject(state))
        w.center()
        // While setup works (connect, restart) the window can't close: its results would be lost, and reopening could
        // start a second run.
        let delegate = SetupWindowDelegate(model: model)
        self.delegate = delegate
        w.delegate = delegate
        workingWatch = model.$working.sink { [weak w] working in w?.standardWindowButton(.closeButton)?.isEnabled = !working }
        model.onClose = { [weak self] in self?.window?.close() }
        model.onOpenOffice = { [weak self] in self?.openDropdown?() }
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // Closing with the red button counts as skipping.
                if !state.settings.setup.seen { state.setSetup(SetupSettings(seen: true, state: nil)) }
                self?.window = nil
                self?.model = nil
                self?.delegate = nil
                self?.workingWatch = nil
                if let token = self?.closeObserver { NotificationCenter.default.removeObserver(token) }
                self?.closeObserver = nil
            }
        }
        window = w
        if offscreen {
            w.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
            w.orderFrontRegardless()
            return
        }
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Keeps the setup window open while setup works.
@MainActor
final class SetupWindowDelegate: NSObject, NSWindowDelegate {
    weak var model: SetupModel?
    init(model: SetupModel) { self.model = model }
    func windowShouldClose(_ sender: NSWindow) -> Bool { !(model?.working ?? false) }
}
