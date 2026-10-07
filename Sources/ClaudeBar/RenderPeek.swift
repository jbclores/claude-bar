import AppKit
import ClaudeBarCore
import SwiftUI

/// `ClaudeBar --render-peek <out.png> [x,y]`: draws the office peek offscreen with live data (and the pointer
/// at x,y if given), saves it as a PNG and quits. For checking the layout without a screen.
@MainActor
enum RenderPeek {
    static func runIfRequested(state: AppState) -> Bool {
        if RenderLabel.runIfRequested(state: state) { return true }
        if TestTabs.runIfRequested(state: state) { return true }
        if TestZoom.runIfRequested(state: state) { return true }
        if let tab = flag("--render-dropdown").flatMap({ DropdownTab(rawValue: $0.1 ?? "") }), let out = flag("--render-dropdown")?.0 {
            renderWindow(DropdownView(forcedTab: tab).environmentObject(state).environmentObject(PeekPointer()), width: 500, to: out)
            return true
        }
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-peek"), i + 1 < args.count else { return false }
        let out = URL(fileURLWithPath: args[i + 1])
        let pointer = PeekPointer()
        if i + 2 < args.count {
            let xy = args[i + 2].split(separator: ",").compactMap { Double($0) }
            if xy.count == 2 { pointer.location = CGPoint(x: xy[0], y: xy[1]) }
        }
        let size = OfficePeekView.size
        let host = NSHostingView(rootView: OfficePeekView().environmentObject(state).environmentObject(pointer).environmentObject(RoomZoom())
            .background(renderLight ? Color(white: 0.93) : Color(white: 0.16))
            .environment(\.colorScheme, renderLight ? .light : .dark))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: renderLight ? .aqua : .darkAqua)
        window.backgroundColor = NSColor(white: renderLight ? 0.93 : 0.16, alpha: 1) // what the popover looks like
        window.contentView = host
        window.orderFrontRegardless()
        if let flip = ProcessInfo.processInfo.environment["CLAUDEBAR_RENDER_FLIP_AT"].flatMap(Double.init),
           let mid = ProcessInfo.processInfo.environment["CLAUDEBAR_RENDER_MIDWALK"].flatMap(Double.init) {
            // Capture the live window mid-walk (a fresh render has no walk in progress).
            DispatchQueue.main.asyncAfter(deadline: .now() + flip + 0.3) { state.replayOffice() }
            DispatchQueue.main.asyncAfter(deadline: .now() + flip + 0.3 + mid) {
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: out)
                exit(0)
            }
            return true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            // SwiftUI's own renderer: the window capture misses colour multiply and blend modes (the night room).
            let zoom = RoomZoom()
            if let factor = ProcessInfo.processInfo.environment["CLAUDEBAR_RENDER_ZOOM"].flatMap(Double.init) {
                zoom.roomRect = CGRect(x: 12, y: 36, width: OfficePeekView.size.width - 24, height: OfficeRoomView.height)
                let at = (ProcessInfo.processInfo.environment["CLAUDEBAR_RENDER_ZOOM_AT"] ?? "120,110").split(separator: ",").compactMap { Double($0) }
                zoom.renderZoom(CGFloat(factor), at: CGPoint(x: at.first ?? 120, y: at.last ?? 110))
            }
            let content = OfficePeekView().environmentObject(state).environmentObject(pointer).environmentObject(zoom)
                .background(renderLight ? Color(white: 0.93) : Color(white: 0.16))
                .environment(\.colorScheme, renderLight ? .light : .dark)
            let renderer = ImageRenderer(content: content.frame(width: size.width, height: size.height))
            renderer.scale = 2
            guard let cg = renderer.cgImage else { exit(1) }
            try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: out)
            exit(0)
        }
        return true
    }
}

/// `ClaudeBar --render-label <out.png> [cat pose]`: draws the menu bar label (cat + usage) with live data, or the
/// given cat and pose, on a dark and a light bar, saves it as a PNG and quits.
@MainActor
enum RenderLabel {
    static func runIfRequested(state: AppState) -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-label"), i + 1 < args.count else { return false }
        let out = URL(fileURLWithPath: args[i + 1])
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            Task { @MainActor in
                var shown = state.menuCat
                if i + 3 < args.count, let pose = CatPose(rawValue: args[i + 3]) {
                    shown = MenuBarCat(agentId: "forced", cat: args[i + 2], pose: pose)
                }
                var icon = MenuBarIcon.fallback
                if let shown, let loaded = await MenuBarIcon.load(shown, art: state.art) { icon = loaded }
                let title = MenuBarTitle.make(usage: state.output.usage, attention: state.needsAttention)
                let size = NSSize(width: 220, height: 56)
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                rep.size = size
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                for (row, dark) in [(1, true), (0, false)] {
                    let y = CGFloat(row) * 28
                    (dark ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
                    NSRect(x: 0, y: y, width: size.width, height: 28).fill()
                    let img = icon.isTemplate ? tinted(icon, dark ? .white : .black) : icon
                    img.draw(in: NSRect(x: 10, y: y + (28 - img.size.height) / 2, width: img.size.width, height: img.size.height))
                    let t = NSMutableAttributedString(attributedString: title)
                    t.addAttribute(.foregroundColor, value: dark ? NSColor.white : NSColor.black,
                                   range: NSRange(location: 0, length: 0))
                    t.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: t.length)) { v, r, _ in
                        if v == nil { t.addAttribute(.foregroundColor, value: dark ? NSColor.white : NSColor.black, range: r) }
                    }
                    t.draw(at: NSPoint(x: 14 + img.size.width, y: y + 7))
                }
                try? rep.representation(using: .png, properties: [:])?.write(to: out)
                print("menu cat:", shown.map { "\($0.agentId) \($0.cat) \($0.pose.rawValue)" } ?? "none (fallback)")
                exit(0)
            }
        }
        return true
    }

    private static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}

/// `--flag <a> [b]`: the values after a flag.
@MainActor
private func flag(_ name: String) -> (URL, String?)? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return (URL(fileURLWithPath: args[i + 1]), i + 2 < args.count ? args[i + 2] : nil)
}

/// Draws `view` in an offscreen dark window sized to fit, after live data has had time to arrive; saves and quits.
@MainActor
private func renderWindow<V: View>(_ view: V, width: CGFloat, to out: URL) {
    let host = NSHostingView(rootView: view.background(renderLight ? Color(white: 0.93) : Color(white: 0.16))
            .environment(\.colorScheme, renderLight ? .light : .dark))
    let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: width, height: 600),
                          styleMask: .borderless, backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .darkAqua)
    window.contentView = host
    window.orderFrontRegardless()
    DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
        let size = host.fittingSize
        window.setContentSize(size)
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: out)
            exit(0)
        }
    }
}

/// Renders in light mode with CLAUDEBAR_RENDER_LIGHT=1 (dark otherwise).
private var renderLight: Bool { ProcessInfo.processInfo.environment["CLAUDEBAR_RENDER_LIGHT"] == "1" }

/// `ClaudeBar --test-tabs`: opens the live dropdown (DropdownController) in an offscreen window, clicks the
/// centre of each tab once with real mouse events, and prints the tab shown after each click. Clicks nothing else.
@MainActor
enum TestTabs {
    static func runIfRequested(state: AppState) -> Bool {
        guard CommandLine.arguments.contains("--test-tabs") else { return false }
        if let start = ProcessInfo.processInfo.environment["CLAUDEBAR_START_TAB"] {
            UserDefaults.standard.set(start, forKey: TabSelection.key)
        }
        let controller = DropdownController(state: state)
        let window = KeyWindow(contentViewController: controller)
        window.styleMask = [.borderless]
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(white: 0.16, alpha: 1)
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        func capture(_ name: String) {
            guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            let image = NSImage(size: view.bounds.size)
            image.lockFocus(); NSColor(white: 0.16, alpha: 1).setFill(); view.bounds.fill(); rep.draw(in: view.bounds); image.unlockFocus()
            if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: "/tmp/cb-mock/tab-\(name.lowercased()).png"))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if controller.preferredContentSize.height > 0 { window.setContentSize(controller.preferredContentSize) }
            guard let control = findControl(in: window.contentView!) else { print("no tab control found"); exit(1) }
            print("start:", UserDefaults.standard.string(forKey: TabSelection.key) ?? "-", "dropdown size:", controller.preferredContentSize)
            for v in window.contentView!.subviews {
                print("  piece:", type(of: v), "frame:", v.frame, "fitting:", v.fittingSize)
            }
            print("  stack:", window.contentView!.frame)
            var remaining: [(String, Int)] = [("Projects", 1), ("Settings", 2), ("Office", 0), ("Projects", 1)]
            func next() {
                guard !remaining.isEmpty else {
                    UserDefaults.standard.set("office", forKey: TabSelection.key)
                    exit(0)
                }
                let (name, index) = remaining.removeFirst()
                let frame = control.convert(control.bounds, to: nil)
                let segment = frame.width / CGFloat(control.segmentCount)
                let point = NSPoint(x: frame.minX + segment * (CGFloat(index) + 0.5), y: frame.midY)
                let hit = window.contentView!.hitTest(window.contentView!.superview!.convert(point, from: nil))
                // Queue the mouse-up first: a native control tracks a press by reading it from the event queue.
                NSApp.postEvent(NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                   windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!, atStart: false)
                window.sendEvent(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if controller.preferredContentSize.height > 0 { window.setContentSize(controller.preferredContentSize) }
                    capture(name)
                    print("clicked \(name) (hit \(hit.map { String(describing: type(of: $0)) } ?? "nothing")) →",
                          UserDefaults.standard.string(forKey: TabSelection.key) ?? "-", "· dropdown height", controller.preferredContentSize.height)
                    next()
                }
            }
            next()
        }
        return true
    }

    private static func findControl(in view: NSView) -> NSSegmentedControl? {
        if let control = view as? NSSegmentedControl { return control }
        for sub in view.subviews { if let found = findControl(in: sub) { return found } }
        return nil
    }
}

/// A borderless window that can take clicks and keyboard focus, like the popover's.
final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}


/// `ClaudeBar --test-zoom`: opens the live dropdown offscreen on the Office tab and sends zoom gestures to the room
/// only (double-click, drag, ⌘-scroll, a click on the "1×" pill), printing the zoom after each. Clicks nothing else.
@MainActor
enum TestZoom {
    static func runIfRequested(state: AppState) -> Bool {
        guard CommandLine.arguments.contains("--test-zoom") else { return false }
        UserDefaults.standard.set("office", forKey: TabSelection.key)
        let controller = DropdownController(state: state)
        let window = KeyWindow(contentViewController: controller)
        window.styleMask = [.borderless]
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { MainActor.assumeIsolated {
            if controller.preferredContentSize.height > 0 { window.setContentSize(controller.preferredContentSize) }
            let zoom = controller.roomZoom
            guard zoom.roomRect.width > 0, let host = findHost(in: window.contentView!) else { print("room not found"); exit(1) }
            // Window points for room points (the host is flipped: top-left origin, like the office space).
            @MainActor func windowPoint(_ office: CGPoint) -> NSPoint { host.convert(office, to: nil) }
            let centre = CGPoint(x: zoom.roomRect.midX, y: zoom.roomRect.midY)
            @MainActor func mouse(_ type: NSEvent.EventType, _ p: CGPoint, clicks: Int = 1) {
                window.sendEvent(NSEvent.mouseEvent(with: type, location: windowPoint(p), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!)
            }
            @MainActor func report(_ step: String) { print(step, "→ scale", String(format: "%.2f", zoom.view.scale), "offset", zoom.view.offset) }
            print("room:", zoom.roomRect)
            mouse(.leftMouseDown, centre, clicks: 2); mouse(.leftMouseUp, centre, clicks: 2)
            report("double-click")
            mouse(.leftMouseDown, centre); mouse(.leftMouseDragged, CGPoint(x: centre.x + 40, y: centre.y + 20)); mouse(.leftMouseUp, CGPoint(x: centre.x + 40, y: centre.y + 20))
            report("drag right/down")
            if let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 40, wheel2: 0, wheel3: 0) {
                cg.flags = .maskCommand
                // CGEvent locations have a top-left origin on the main display; AppKit's are bottom-left.
                let screen = window.convertPoint(toScreen: windowPoint(centre))
                cg.location = CGPoint(x: screen.x, y: (NSScreen.screens.first?.frame.height ?? 0) - screen.y)
                // Straight to the room's container: an offscreen window doesn't route synthetic scrolls.
                if let e = NSEvent(cgEvent: cg), let container = host.superview { container.scrollWheel(with: e) }
            }
            report("⌘-scroll")
            let pill = CGPoint(x: zoom.pillRect.midX, y: zoom.pillRect.midY)
            mouse(.leftMouseDown, pill); mouse(.leftMouseUp, pill)
            report("click 1× pill")
            let before = state.settings.officeLighting
            // The theme button: right end of the usage header's top row (the header is the stack's first view).
            if let header = window.contentView?.subviews.first {
                let f = header.convert(header.bounds, to: nil)
                let button = NSPoint(x: f.maxX - 13, y: f.maxY - 9)
                for t in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    window.sendEvent(NSEvent.mouseEvent(with: t, location: button, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
                }
                print("click ☀️/🌙 → theme", before.rawValue, "→", state.settings.officeLighting.rawValue, "· app appearance", NSApp.appearance?.name.rawValue ?? "follows the Mac")
                for t in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    window.sendEvent(NSEvent.mouseEvent(with: t, location: button, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
                }
                print("click it again → theme", state.settings.officeLighting.rawValue, "· app appearance", NSApp.appearance?.name.rawValue ?? "follows the Mac")
            }
            state.setOfficeLighting(before)
            exit(0)
        } }
        return true
    }

    private static func findHost(in view: NSView) -> NSView? {
        if view is ZoomingContainer { return view.subviews.first }
        for sub in view.subviews { if let found = findHost(in: sub) { return found } }
        return nil
    }
}
