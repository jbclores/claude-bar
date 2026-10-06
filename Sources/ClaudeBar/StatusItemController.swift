import AppKit
import Combine
import ClaudeBarCore
import SwiftUI

/// The menu bar item: its label, the dropdown on click, and the office peek on hover.
@MainActor
final class StatusItemController: NSResponder {
    private let state: AppState
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let dropdown = NSPopover()
    private let peek = NSPopover()
    private let pointer = PeekPointer()
    private var subscriptions = Set<AnyCancellable>()
    private var showTimer: Timer?
    private var hideTimer: Timer?
    private var overIcon = false
    private var overPeek = false

    init(state: AppState) {
        self.state = state
        super.init()

        dropdown.behavior = .transient
        let host = NSHostingController(rootView: DropdownView().environmentObject(state))
        host.sizingOptions = .preferredContentSize
        dropdown.contentViewController = host

        peek.behavior = .applicationDefined
        peek.animates = false
        let peekView = PeekContainerView(
            content: OfficePeekView().environmentObject(state).environmentObject(pointer),
            size: OfficePeekView.size)
        peekView.onPointer = { [weak self] point in self?.peekPointer(point) }
        let peekController = NSViewController()
        peekController.view = peekView
        peek.contentViewController = peekController
        peek.contentSize = OfficePeekView.size

        if let button = item.button {
            button.target = self
            button.action = #selector(toggleDropdown)
            button.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                                  owner: self, userInfo: nil))
        }
        state.$output.combineLatest(state.$needsAttention)
            .sink { [weak self] output, attention in self?.updateTitle(output, attention: attention) }
            .store(in: &subscriptions)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func updateTitle(_ output: StatusOutput, attention: Bool) {
        item.button?.attributedTitle = MenuBarTitle.make(usage: output.usage, attention: attention)
    }

    @objc private func toggleDropdown() {
        showTimer?.invalidate()
        peek.performClose(nil)
        if dropdown.isShown {
            dropdown.performClose(nil)
            return
        }
        guard let button = item.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        dropdown.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        state.acknowledge()
    }

    // MARK: Hover peek: opens after 0.3s on the icon, closes 0.25s after the pointer leaves icon and peek.

    override func mouseEntered(with event: NSEvent) {
        overIcon = true
        hideTimer?.invalidate()
        guard !peek.isShown, !dropdown.isShown else { return }
        showTimer?.invalidate()
        showTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.showPeek() }
        }
    }

    override func mouseExited(with event: NSEvent) {
        overIcon = false
        showTimer?.invalidate()
        scheduleHide()
    }

    private func peekPointer(_ point: CGPoint?) {
        pointer.location = point
        overPeek = point != nil
        if overPeek { hideTimer?.invalidate() } else { scheduleHide() }
    }

    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.overIcon, !self.overPeek else { return }
                self.peek.performClose(nil)
                self.pointer.location = nil
            }
        }
    }

    private func showPeek() {
        guard overIcon, !dropdown.isShown, !peek.isShown, let button = item.button else { return }
        peek.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        state.acknowledge()
    }
}

/// Hosts the peek and reports the pointer (top-left origin, nil when it leaves), even while ClaudeBar is inactive.
final class PeekContainerView: NSView {
    var onPointer: ((CGPoint?) -> Void)?

    init<Content: View>(content: Content, size: CGSize) {
        super.init(frame: NSRect(origin: .zero, size: size))
        let host = NSHostingView(rootView: content)
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func mouseEntered(with event: NSEvent) { report(event) }
    override func mouseMoved(with event: NSEvent) { report(event) }
    override func mouseExited(with event: NSEvent) { onPointer?(nil) }

    private func report(_ event: NSEvent) {
        onPointer?(convert(event.locationInWindow, from: nil))
    }
}

enum MenuBarTitle {
    /// "◆ 42% · 18%" (5h · 7d), each colored by level; "◆•" when something needs the user; "◆ —" with no data.
    static func make(usage: UsageSummary, attention: Bool) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let plain: [NSAttributedString.Key: Any] = [.font: font]
        let s = NSMutableAttributedString(string: "◆", attributes: plain)
        if attention {
            s.append(NSAttributedString(string: "•", attributes: [.font: font, .foregroundColor: NSColor(Theme.waiting)]))
        }
        guard usage.fiveHourPct != nil || usage.sevenDayPct != nil else {
            s.append(NSAttributedString(string: " —", attributes: plain))
            return s
        }
        func pct(_ value: Double?) -> NSAttributedString {
            guard let value else { return NSAttributedString(string: "—", attributes: plain) }
            return NSAttributedString(string: Format.percent(value),
                                      attributes: [.font: font, .foregroundColor: Theme.nsColor(UsageLevel(percent: value))])
        }
        s.append(NSAttributedString(string: " ", attributes: plain))
        s.append(pct(usage.fiveHourPct))
        s.append(NSAttributedString(string: " · ", attributes: plain))
        s.append(pct(usage.sevenDayPct))
        return s
    }
}
