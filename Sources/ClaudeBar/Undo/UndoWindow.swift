import AppKit
import ClaudeBarCore
import Combine
import SwiftUI

/// The undo window, from Settings → Undo ClaudeBar's changes….
@MainActor
final class UndoWindow {
    static let shared = UndoWindow()
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?
    private var delegate: UndoWindowDelegate?
    private var workingWatch: AnyCancellable?
    /// The open window's model (the click test drives it; nil while closed).
    private(set) var model: UndoModel?

    /// `offscreen`: the click test's window, far off any screen and without activating the app.
    func open(state: AppState, env: SetupEnvironment = .real, offscreen: Bool = false) {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let model = UndoModel(state: state, env: env)
        self.model = model
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: UndoView.size), styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = UndoText.title
        w.isReleasedWhenClosed = false
        w.hidesOnDeactivate = false
        w.contentView = NSHostingView(rootView: UndoView(model: model).environmentObject(state))
        w.center()
        // While undo works the window can't close: its results would be lost, and reopening could start a second run.
        let delegate = UndoWindowDelegate(model: model)
        self.delegate = delegate
        w.delegate = delegate
        workingWatch = model.$working.sink { [weak w] working in w?.standardWindowButton(.closeButton)?.isEnabled = !working }
        model.onClose = { [weak self] in self?.window?.close() }
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // After "Also remove", closing the window by any route still quits ClaudeBar.
                let removed = self?.model?.removed ?? false
                self?.window = nil
                self?.model = nil
                self?.delegate = nil
                self?.workingWatch = nil
                if let token = self?.closeObserver { NotificationCenter.default.removeObserver(token) }
                self?.closeObserver = nil
                if removed { NSApp.terminate(nil) }
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

/// Keeps the undo window open while undo works.
@MainActor
final class UndoWindowDelegate: NSObject, NSWindowDelegate {
    weak var model: UndoModel?
    init(model: UndoModel) { self.model = model }
    func windowShouldClose(_ sender: NSWindow) -> Bool { !(model?.working ?? false) }
}
