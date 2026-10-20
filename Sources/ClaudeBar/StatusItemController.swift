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
    private lazy var dropdownController = DropdownController(state: state)
    private let peek = NSPopover()
    private let pointer = PeekPointer()
    private let peekZoom = RoomZoom()
    private let peekFloors = FloorSelection(alwaysFollow: true)
    private var subscriptions = Set<AnyCancellable>()
    private var showTimer: Timer?
    private var hideTimer: Timer?
    private var overIcon = false
    private var overPeek = false
    private var iconCache: [String: NSImage] = [:]
    private var iconTask: Task<Void, Never>?

    init(state: AppState) {
        self.state = state
        super.init()

        dropdown.behavior = .transient
        dropdown.contentViewController = dropdownController

        peek.behavior = .applicationDefined
        peek.animates = false
        let peekView = PeekContainerView(
            content: OfficePeekView().environmentObject(state).environmentObject(pointer).environmentObject(peekZoom).environmentObject(peekFloors),
            size: OfficePeekView.size, zoom: peekZoom)
        peekView.onPointer = { [weak self] point in self?.peekPointer(point) }
        peekView.cursor = state.roomCursor
        peekView.onEnterRoom = { [weak self] in self?.activateForPeek() }
        let peekController = NSViewController()
        peekController.view = peekView
        peek.contentViewController = peekController
        peek.contentSize = OfficePeekView.size
        dropdownController.onTabChange = { [weak self] in self?.officeOnScreenChanged() }
        // The click meow and the elevator ding only play while the office is on screen.
        for name in [NSPopover.didShowNotification, NSPopover.didCloseNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.officeOnScreenChanged() }
            }
        }

        if let button = item.button {
            button.imagePosition = .imageLeft
            button.image = MenuBarIcon.fallback
            button.target = self
            button.action = #selector(toggleDropdown)
            button.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                                  owner: self, userInfo: nil))
        }
        state.$output.combineLatest(state.$needsAttention)
            .sink { [weak self] output, attention in self?.updateTitle(output, attention: attention) }
            .store(in: &subscriptions)
        // The theme (☀️/🌙): popovers follow the menu bar's look unless told; nil follows the Mac.
        state.$appearance
            .sink { [weak self] appearance in self?.applyTheme(appearance) }
            .store(in: &subscriptions)
        // Following the Mac: re-apply when its theme changes.
        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.applyTheme(self.state.appearance)
            }
            .store(in: &subscriptions)
        // The Office tab comes and goes with "I don't use Cat Office" (and a Cat Office running anyway).
        state.$settings.map(\.setup).removeDuplicates().combineLatest(state.$office.map { $0 != nil }.removeDuplicates())
            .sink { [weak self] _, _ in DispatchQueue.main.async { self?.dropdownController.updateTabs() } }
            .store(in: &subscriptions)
        // The shortcut opens and closes the dropdown; re-registered whenever it changes in Settings.
        HotKeyCenter.shared.onPress[.open] = { [weak self] in self?.toggleDropdown() }
        state.$settings.map(\.shortcut).removeDuplicates()
            .sink { [weak self] shortcut in self?.state.shortcutTaken = !HotKeyCenter.shared.register(shortcut, slot: .open) }
            .store(in: &subscriptions)
        // Hold the talk shortcut to talk: registered only while "Talk to ClaudeBar" is on.
        HotKeyCenter.shared.onPress[.talk] = { [weak self] in self?.state.voice.keyDown() }
        HotKeyCenter.shared.onRelease[.talk] = { [weak self] in self?.state.voice.keyUp() }
        state.$settings.map { $0.voice.talk ? $0.voice.talkShortcut : nil }.removeDuplicates()
            .sink { [weak self] shortcut in
                guard let self, self.state.sideEffects else { return }
                self.state.talkShortcutTaken = !HotKeyCenter.shared.register(shortcut, slot: .talk)
            }
            .store(in: &subscriptions)
        state.$voiceListening.removeDuplicates()
            .sink { [weak self] listening in self?.showIcon(listening: listening) }
            .store(in: &subscriptions)
        state.$menuCat.removeDuplicates()
            .sink { [weak self] cat in self?.updateIcon(cat) }
            .store(in: &subscriptions)

        // "Open the office" in the setup window opens the dropdown.
        SetupWindow.shared.openDropdown = { [weak self] in
            guard let self, !self.dropdown.isShown else { return }
            self.toggleDropdown()
        }
        // Onboarding: the setup window opens by itself once (not for a setup that already works).
        if state.sideEffects {
            Task { @MainActor in
                if await state.inferSetupIfNeeded() {
                    try? await Task.sleep(for: .seconds(1))
                    SetupWindow.shared.open(state: state)
                }
            }
        }
    }

    private func applyTheme(_ appearance: NSAppearance?) {
        let target = appearance ?? Self.macAppearance
        for popover in [dropdown, peek] {
            popover.appearance = target
            popover.contentViewController?.view.window?.appearance = target
        }
    }

    /// The Mac's own light or dark theme (the menu bar's look can differ, e.g. over a dark wallpaper).
    private static var macAppearance: NSAppearance? {
        NSAppearance(named: UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" ? .darkAqua : .aqua)
    }

    /// The cat now in the menu bar (without the microphone).
    private var catIcon = MenuBarIcon.fallback

    /// Shows `cat` (or the cat already shown), with a microphone beside it while ClaudeBar listens.
    private func showIcon(_ cat: NSImage? = nil, listening: Bool? = nil) {
        if let cat { catIcon = cat }
        item.button?.image = listening ?? state.voiceListening ? MenuBarIcon.withMic(catIcon) : catIcon
    }

    /// The menu bar cat: from the icon cache, else trimmed from the art cache; the plain cat symbol meanwhile.
    private func updateIcon(_ cat: MenuBarCat?) {
        iconTask?.cancel()
        guard let cat else {
            showIcon(MenuBarIcon.fallback)
            return
        }
        let key = "\(cat.cat)-\(cat.pose.rawValue)"
        if let cached = iconCache[key] {
            showIcon(cached)
            return
        }
        iconTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let image = await MenuBarIcon.load(cat, art: self.state.art)
            guard !Task.isCancelled, self.state.menuCat == cat else { return }
            if let image { self.iconCache[key] = image }
            self.showIcon(image ?? MenuBarIcon.fallback)
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// The popup or the dropdown opened or closed, or the dropdown switched tabs: sounds and music follow.
    private func officeOnScreenChanged() {
        state.officeVisible = peek.isShown || dropdown.isShown
        state.peekShownSince = peek.isShown ? (state.peekShownSince ?? Date()) : nil
        state.officeTabShown = dropdown.isShown && dropdownController.showsOffice
    }

    private func updateTitle(_ output: StatusOutput, attention: Bool) {
        item.button?.attributedTitle = MenuBarTitle.make(usage: output.usage, attention: attention)
        item.button?.setAccessibilityLabel(MenuBarTitle.spoken(usage: output.usage, attention: attention))
        dropdownController.updateAttention(attention)
    }

    @objc private func toggleDropdown() {
        showTimer?.invalidate()
        // Opening the dropdown keeps ClaudeBar active on purpose: don't hand focus back when the peek goes.
        appBeforePeek = nil
        peek.performClose(nil)
        if dropdown.isShown {
            dropdown.performClose(nil)
            return
        }
        guard let button = item.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        dropdownController.resetZoom()
        dropdownController.updateTabs()
        dropdown.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        state.acknowledge()
    }

    // MARK: Hover peek: opens after 0.3s on the icon, closes 0.25s after the pointer leaves icon and peek.

    override func mouseEntered(with event: NSEvent) {
        overIcon = true
        hideTimer?.invalidate()
        guard state.settings.hoverPeek, state.officeShown, !peek.isShown, !dropdown.isShown else { return }
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

    /// The app that was active before the pointer went into the peek's room: it gets focus back when the peek closes.
    private var appBeforePeek: NSRunningApplication?

    /// Bongo Cat only shows while ClaudeBar is active: activate it when the pointer goes into the peek's room.
    private func activateForPeek() {
        guard !NSApp.isActive else { return }
        appBeforePeek = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in self?.state.roomCursor.moved(inRoom: true) }
    }

    /// The peek closed: hand focus back to the app that had it, unless the dropdown has since been opened.
    private func returnFocusAfterPeek() {
        defer { appBeforePeek = nil }
        guard let app = appBeforePeek, NSApp.isActive, !dropdown.isShown,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        app.activate()
    }

    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.overIcon, !self.overPeek else { return }
                self.peek.performClose(nil)
                self.pointer.location = nil
                self.returnFocusAfterPeek()
            }
        }
    }

    private func showPeek() {
        guard overIcon, !dropdown.isShown, !peek.isShown, let button = item.button else { return }
        peekZoom.reset()
        peek.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        state.acknowledge()
    }
}

/// Hosts the peek and reports the pointer (top-left origin, nil when it leaves), even while ClaudeBar is inactive.
final class PeekContainerView: NSView {
    var onPointer: ((CGPoint?) -> Void)?
    /// Bongo Cat over the room, as in Cat Office.
    var cursor: RoomCursor?
    /// The pointer went into the room (macOS only shows an active app's cursor, so the controller activates ClaudeBar).
    var onEnterRoom: (() -> Void)?
    private let zoom: RoomZoom
    private var host: NSView!

    init<Content: View>(content: Content, size: CGSize, zoom: RoomZoom) {
        self.zoom = zoom
        super.init(frame: NSRect(origin: .zero, size: size))
        let host = ClickThroughHostingView(rootView: content)
        self.host = host
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func mouseEntered(with event: NSEvent) { report(event) }
    override func mouseMoved(with event: NSEvent) { report(event) }
    override func mouseExited(with event: NSEvent) {
        onPointer?(nil)
        cursor?.moved(inRoom: false)
    }

    private func report(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onPointer?(point)
        let inRoom = zoom.contains(point)
        if inRoom, cursor?.inRoom != true { onEnterRoom?() }
        cursor?.moved(inRoom: inRoom)
    }

    // Zoom and pan over the room (pinch, ⌘-scroll, scroll, drag, double-click), even while ClaudeBar isn't active.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard frame.contains(point) else { return nil }
        return zoom.contains(convert(point, from: superview)) ? self : super.hitTest(point)
    }

    // Unused events go up the responder chain (super), never down to the host: its default passes them
    // back up to this view, which looped until the stack overflowed.
    private func officePoint(_ event: NSEvent) -> CGPoint {
        // Events without a window (e.g. built from a CGEvent) carry screen coordinates.
        let inWindow = event.window == nil ? (window?.convertPoint(fromScreen: event.locationInWindow) ?? event.locationInWindow) : event.locationInWindow
        return self.convert(inWindow, from: nil)
    }

    override func magnify(with event: NSEvent) { if !zoom.handle(event, at: officePoint(event)) { super.magnify(with: event) } }
    override func scrollWheel(with event: NSEvent) { if !zoom.handle(event, at: officePoint(event)) { super.scrollWheel(with: event) } }
    override func mouseDown(with event: NSEvent) {
        cursor?.pressed()
        if !zoom.handle(event, at: officePoint(event)) { super.mouseDown(with: event) }
    }
    override func mouseDragged(with event: NSEvent) { if !zoom.handle(event, at: officePoint(event)) { super.mouseDragged(with: event) } }
    override func mouseUp(with event: NSEvent) {
        cursor?.released()
        if !zoom.handle(event, at: officePoint(event)) { super.mouseUp(with: event) }
    }
    override func cursorUpdate(with event: NSEvent) {
        if cursor?.inRoom == true { cursor?.moved(inRoom: true) } else { super.cursorUpdate(with: event) }
    }
}

@MainActor
enum MenuBarIcon {
    /// Shown while Cat Office is offline or nobody is in the office.
    static let fallback: NSImage = {
        let image = NSImage(systemSymbolName: "cat", accessibilityDescription: "ClaudeBar")!
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))!
        image.isTemplate = true
        return image
    }()

    /// `cat` with a small microphone after it (push-to-talk is listening). A template cat stays a template; a
    /// coloured one gets a microphone in the menu bar's text colour.
    static func withMic(_ cat: NSImage) -> NSImage {
        guard let mic = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Listening")?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .medium)) else { return cat }
        let gap: CGFloat = 2
        let size = NSSize(width: cat.size.width + gap + mic.size.width, height: max(cat.size.height, mic.size.height))
        let image = NSImage(size: size, flipped: false) { _ in
            cat.draw(in: NSRect(x: 0, y: ((size.height - cat.size.height) / 2).rounded(), width: cat.size.width, height: cat.size.height))
            let micRect = NSRect(x: cat.size.width + gap, y: ((size.height - mic.size.height) / 2).rounded(),
                                 width: mic.size.width, height: mic.size.height)
            mic.draw(in: micRect)
            if !cat.isTemplate {
                // Tint the (black) symbol to the text colour, resolved when drawn.
                NSColor.labelColor.set()
                micRect.fill(using: .sourceAtop)
            }
            return true
        }
        image.isTemplate = cat.isTemplate
        image.accessibilityDescription = "ClaudeBar, listening"
        return image
    }

    /// Fits every pose into the same box, so a sleeping cat isn't smaller than a standing one.
    static let box = NSSize(width: 22, height: 18)

    static func load(_ cat: MenuBarCat, art: ArtCache) async -> NSImage? {
        guard let data = await art.catImage(cat: cat.cat, pose: cat.pose),
              let trimmed = ArtCache.trimmed(data), let image = NSImage(data: trimmed) else { return nil }
        return fitted(image)
    }

    /// Aspect-fit and centered on a canvas of exactly `box`, so the text after it never shifts between poses.
    static func fitted(_ image: NSImage) -> NSImage {
        let scale = min(box.width / image.size.width, box.height / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        return NSImage(size: box, flipped: false) { _ in
            image.draw(in: NSRect(x: ((box.width - size.width) / 2).rounded(), y: 0, width: size.width, height: size.height))
            return true
        }
    }
}

enum MenuBarTitle {
    /// "42% · 18%" (5h · 7d) after the icon, in the menu bar's own color until a level is worth a glance (warn,
    /// high); a leading amber "•" when something needs the user; "—" with no data.
    static func make(usage: UsageSummary, attention: Bool) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let plain: [NSAttributedString.Key: Any] = [.font: font]
        let s = NSMutableAttributedString(string: "", attributes: plain)
        if attention {
            s.append(NSAttributedString(string: "•", attributes: [.font: font, .foregroundColor: NSColor(Theme.waiting)]))
        }
        guard usage.fiveHourPct != nil || usage.sevenDayPct != nil else {
            s.append(NSAttributedString(string: " —", attributes: plain))
            return s
        }
        func pct(_ value: Double?) -> NSAttributedString {
            guard let value else { return NSAttributedString(string: "—", attributes: plain) }
            let level = UsageLevel(percent: value)
            guard level != .ok else { return NSAttributedString(string: Format.percent(value), attributes: plain) }
            return NSAttributedString(string: Format.percent(value), attributes: [.font: font, .foregroundColor: Theme.nsColor(level)])
        }
        s.append(NSAttributedString(string: " ", attributes: plain))
        s.append(pct(usage.fiveHourPct))
        s.append(NSAttributedString(string: " · ", attributes: plain))
        s.append(pct(usage.sevenDayPct))
        return s
    }

    /// What VoiceOver reads for the label: which number is which.
    static func spoken(usage: UsageSummary, attention: Bool) -> String {
        let parts = [attention ? "A cat needs you" : nil,
                     usage.fiveHourPct.map { "5-hour limit \(Format.percent($0)) used" },
                     usage.sevenDayPct.map { "7-day limit \(Format.percent($0)) used" }].compactMap { $0 }
        return (["ClaudeBar"] + parts).joined(separator: ", ")
    }
}
