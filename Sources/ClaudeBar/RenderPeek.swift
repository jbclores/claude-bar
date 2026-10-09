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
        if TestSetup.runIfRequested() { return true }
        if TestUndo.runIfRequested() { return true }
        if RenderRoutes.runIfRequested(state: state) { return true }
        // `--render-help <out.png>`: the ? help panel.
        if let out = flag("--render-help")?.0 {
            renderWindow(HelpPanel().environmentObject(state), width: 340, to: out)
            return true
        }
        if let tab = flag("--render-dropdown").flatMap({ DropdownTab(rawValue: $0.1 ?? "") }), let out = flag("--render-dropdown")?.0 {
            SettingsTabView.startOpen = ProcessInfo.processInfo.environment["CLAUDEBAR_RENDER_SETTINGS_OPEN"] == "1"
            renderWindow(DropdownView(forcedTab: tab).environmentObject(state).environmentObject(PeekPointer()), width: 500, to: out)
            return true
        }
        // `--render-setup <welcome|find|find-searching|connect|connect-running-unpatched|connect-none|done|done-restart> <out.png>`: the setup window over
        // temp folders only (a fake home with one Cat Office, a claude folder with its own status line).
        if let i = CommandLine.arguments.firstIndex(of: "--render-setup"), i + 2 < CommandLine.arguments.count {
            let args = CommandLine.arguments
            guard let model = setupModel(step: args[i + 1], state: state) else { print("unknown setup step \(args[i + 1])"); exit(1) }
            renderWindow(SetupView(model: model).environmentObject(state), width: SetupView.size.width,
                         to: URL(fileURLWithPath: args[i + 2]))
            return true
        }
        // `--render-undo <choose|choose-running|choose-working|choose-nothing|choose-greyed|done|done-failed|done-removed> <out.png>`: the undo window
        // over a temp environment (never the real Mac).
        if let i = CommandLine.arguments.firstIndex(of: "--render-undo"), i + 2 < CommandLine.arguments.count {
            let args = CommandLine.arguments
            guard let model = undoModel(mode: args[i + 1], state: state) else { print("unknown undo mode \(args[i + 1])"); exit(1) }
            renderWindow(UndoView(model: model).environmentObject(state), width: UndoView.size.width,
                         to: URL(fileURLWithPath: args[i + 2]))
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
        let host = NSHostingView(rootView: OfficePeekView().environmentObject(state).environmentObject(pointer).environmentObject(RoomZoom()).environmentObject((ProcessInfo.processInfo.environment["CLAUDEBAR_RENDER_FLOOR"] != nil ? FloorSelection.forRender() : FloorSelection(alwaysFollow: true)))
            .background(renderLight ? Color(white: 0.93) : Color(white: 0.16))
            .environment(\.colorScheme, renderLight ? .light : .dark))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: renderLight ? .aqua : .darkAqua)
        window.backgroundColor = NSColor(white: renderLight ? 0.93 : 0.16, alpha: 1) // what the popover looks like
        window.contentView = host
        window.orderFrontRegardless()
        func captureHost() {
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: out)
        }
        // The peek is on screen: the office's own life runs (after launch has set `sideEffects`, for the render seed).
        DispatchQueue.main.async { state.peekShownSince = Date() }
        // CLAUDEBAR_SIM_REOPEN=<seconds>: the peek closes 4 s in for that long, then opens again (the catch-up places
        // the cats at once); the live window is captured 0.5 s after (CLAUDEBAR_SIM_REOPEN_SHOT; cats walking there would
        // be mid-walk).
        if let closed = ProcessInfo.processInfo.environment["CLAUDEBAR_SIM_REOPEN"].flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { state.peekShownSince = nil }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4 + closed) { state.peekShownSince = Date() }
            let shot = ProcessInfo.processInfo.environment["CLAUDEBAR_SIM_REOPEN_SHOT"].flatMap(Double.init) ?? 0.5
            DispatchQueue.main.asyncAfter(deadline: .now() + 4 + closed + shot) { captureHost(); exit(0) }
            return true
        }
        if let flip = ProcessInfo.processInfo.environment["CLAUDEBAR_RENDER_FLIP_AT"].flatMap(Double.init),
           let mid = ProcessInfo.processInfo.environment["CLAUDEBAR_RENDER_MIDWALK"].flatMap(Double.init) {
            // Capture the live window mid-walk (a fresh render has no walk in progress).
            DispatchQueue.main.asyncAfter(deadline: .now() + flip + 0.3) { state.replayOffice() }
            // A third places file (CLAUDEBAR_RENDER_PLACES_STEP seconds after the second) is posted by one more replay.
            let step = ProcessInfo.processInfo.environment["CLAUDEBAR_RENDER_PLACES_STEP"].flatMap(Double.init) ?? 3
            DispatchQueue.main.asyncAfter(deadline: .now() + flip + 0.3 + step + 0.05) { state.replayOffice() }
            DispatchQueue.main.asyncAfter(deadline: .now() + flip + 0.3 + mid) { captureHost(); exit(0) }
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
            let floors = ProcessInfo.processInfo.environment["CLAUDEBAR_RENDER_FLOOR"] != nil ? FloorSelection.forRender() : FloorSelection(alwaysFollow: true)
            let content = OfficePeekView().environmentObject(state).environmentObject(pointer).environmentObject(zoom).environmentObject(floors)
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
/// A SetupModel over a temp SetupEnvironment (never the real home, ~/.claude or Cat Office), at `step`.
@MainActor
private func setupModel(step: String, state: AppState) -> SetupModel? {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("claudebar-setup-render-\(UUID().uuidString)").resolvingSymlinksInPath()
    let home = root.appendingPathComponent("home")
    let office = home.appendingPathComponent("Documents/projects/cat-office")
    let claude = home.appendingPathComponent(".claude")
    try? fm.createDirectory(at: office.appendingPathComponent("server/agent-bridge"), withIntermediateDirectories: true)
    try? fm.createDirectory(at: claude, withIntermediateDirectories: true)
    try? Data(#"{"name":"cat-office"}"#.utf8).write(to: office.appendingPathComponent("package.json"))
    try? Data(#"{"statusLine":{"type":"command","command":"npx ccstatusline"}}"#.utf8).write(to: claude.appendingPathComponent("settings.json"))
    var env = SetupEnvironment(home: home, claudeDir: claude, resources: root.appendingPathComponent("resources"),
                               bridgeFile: root.appendingPathComponent("bridge.json"))
    // Never the real Cat Office's address: nothing answers, except in the one mode that shows an unpatched, running copy.
    let answering = step == "connect-running-unpatched"
    env.answers = { _ in answering }
    let model = SetupModel(state: state, env: env)
    // The finder over the temp home only (not the real saved folder).
    model.candidates = CatOfficeFinder.candidates(running: nil, saved: nil, roots: CatOfficeFinder.defaultRoots(home: home.path))
    model.chosen = model.candidates.first?.path
    switch step {
    case "welcome": model.step = .welcome
    case "find": model.step = .find
    case "find-searching": model.step = .find; model.searching = true
    case "connect": model.step = .connect
    case "connect-running-unpatched": model.step = .connect; model.somethingAnswers = true
    case "connect-none": model.useNoCatOffice()
    case "done", "done-restart":
        model.step = .done
        model.results["usage"] = StepResult(ok: true, text: "Your status line is kept; ClaudeBar reads its data quietly.")
        model.results["patch"] = StepResult(ok: false, text: "Your Cat Office version doesn't support the extras yet. Nothing was changed, and everything else works as usual.")
        if step == "done-restart" {
            model.results["patch"] = StepResult(ok: true, text: "Patched (a backup of the changed files is in .cat-office/).")
            model.results["start"] = StepResult(ok: true, text: "Cat Office is running: restart it to load the patch.")
            model.needsRestart = true
        }
    default: return nil
    }
    return model
}

/// A temp environment for undo renders and the click test: never the real home, Cat Office, login item or address.
private func undoEnvironment() -> (SetupEnvironment, URL) {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("claudebar-undo-\(UUID().uuidString)").resolvingSymlinksInPath()
    let home = root.appendingPathComponent("home")
    let claude = home.appendingPathComponent(".claude")
    try? fm.createDirectory(at: claude, withIntermediateDirectories: true)
    var env = SetupEnvironment(home: home, claudeDir: claude, resources: SetupEnvironment.real.resources,
                               bridgeFile: root.appendingPathComponent("bridge.json"))
    env.answers = { _ in false }
    env.launchAtLoginOff = { true }
    env.rememberedDir = { nil }
    return (env, root)
}

/// The undo window in a fixed state (rows and results set directly; `load()` never runs).
@MainActor
private func undoModel(mode: String, state: AppState) -> UndoModel? {
    let (env, _) = undoEnvironment()
    let model = UndoModel(state: state, env: env)
    let dir = env.home.appendingPathComponent("Documents/projects/cat-office").path
    let all = UndoPlan.rows(catOfficeDir: dir, unpatch: .patched, statusLine: .wrapped(original: "npx ccstatusline"),
                            canRestore: true, home: env.home.path)
    model.rows = all
    model.ticked = UndoPlan.startTicks(all)
    switch mode {
    case "choose": model.phase = .choose
    case "choose-running": model.phase = .choose; model.somethingAnswers = true
    case "choose-working": model.phase = .choose; model.working = true
    case "choose-nothing":
        model.rows = UndoPlan.rows(catOfficeDir: dir, unpatch: .notPatched, statusLine: .none, canRestore: false, home: env.home.path)
        model.ticked = []
        model.phase = .choose
    case "choose-greyed":
        model.rows = UndoPlan.rows(catOfficeDir: dir, unpatch: .cannotUndo, statusLine: .claudeBar, canRestore: false, home: env.home.path)
        model.ticked = UndoPlan.startTicks(model.rows)
        model.phase = .choose
    case "done":
        model.results = [.unpatch: StepResult(ok: true, text: "Cat Office is unpatched (a backup of the changed files is in .cat-office/)."),
                         .statusLine: StepResult(ok: true, text: "Your old status line is back.")]
        model.doneLines = UndoText.doneLines(results: [.unpatch: true, .statusLine: true], leftOut: false)
        model.needsRestart = true
        model.phase = .done
    case "done-failed":
        model.results = [.unpatch: StepResult(ok: false, text: UndoText.failedSafe + " ClaudeBar couldn't take its patch out cleanly; your backups are in \(dir)/.cat-office/."),
                         .statusLine: StepResult(ok: true, text: "Your old status line is back.")]
        model.doneLines = UndoText.doneLines(results: [.unpatch: false, .statusLine: true], leftOut: false)
        model.phase = .done
    case "done-removed":
        model.results = [.statusLine: StepResult(ok: true, text: "Your old status line is back."),
                         .remove: StepResult(ok: true, text: "Launch at Login is off, and ClaudeBar's files are in the Trash.")]
        model.doneLines = UndoText.doneLines(results: [.statusLine: true, .remove: true], leftOut: false)
        model.phase = .done
    default: return nil
    }
    return model
}

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
            // The tabs as the menu bar item sets them (CLAUDEBAR_RENDER_NO_CAT_OFFICE=1: no Office tab).
            controller.updateTabs()
            if controller.preferredContentSize.height > 0 { window.setContentSize(controller.preferredContentSize) }
            guard let control = findControl(in: window.contentView!) else { print("no tab control found"); exit(1) }
            print("start:", UserDefaults.standard.string(forKey: TabSelection.key) ?? "-", "dropdown size:", controller.preferredContentSize)
            for v in window.contentView!.subviews {
                print("  piece:", type(of: v), "frame:", v.frame, "fitting:", v.fittingSize)
            }
            print("  stack:", window.contentView!.frame)
            var remaining: [(String, Int)] = [("Projects", 1), ("Settings", 2), ("Office", 0), ("Projects", 1), ("Office", 0)]
            func next() {
                guard !remaining.isEmpty else {
                    UserDefaults.standard.set("office", forKey: TabSelection.key)
                    MainActor.assumeIsolated { floorSteps(controller: controller, window: window, state: state) }
                    return
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
                    print("  room area on \(name):", controller.roomZoom.roomRect == .zero ? "none" : "\(controller.roomZoom.roomRect)")
                    print("clicked \(name) (hit \(hit.map { String(describing: type(of: $0)) } ?? "nothing")) →",
                          UserDefaults.standard.string(forKey: TabSelection.key) ?? "-", "· dropdown height", controller.preferredContentSize.height)
                    next()
                }
            }
            next()
        }
        return true
    }

    /// The floor picker: clicks ▲, ▼ and Follow (found by their help tags, nothing else), printing the choice after each.
    private static func floorSteps(controller: DropdownController, window: NSWindow, state: AppState) {
        var steps: [(String, String)] = [("▲", "floor-up"), ("▼", "floor-down"), ("Follow", "floor-follow")]
        let floors = controller.floorSelection
        print("floor before: shown \(floors.shown(state)) · \(floors.choice)")
        func step() {
            guard !steps.isEmpty else { exit(0) }
            let (name, help) = steps.removeFirst()
            if let frame = floors.targets[help] {
                // SwiftUI's .global is the window, from its top-left.
                let point = NSPoint(x: frame.midX, y: window.contentView!.bounds.height - frame.midY)
                let hit = window.contentView!.hitTest(window.contentView!.superview!.convert(point, from: nil))
                print("floor: \(name) at \(frame) → window \(point), hits \(hit.map { String(describing: type(of: $0)) } ?? "nothing")")
                NSApp.postEvent(NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                   windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!, atStart: false)
                window.sendEvent(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
            } else {
                print("floor: click target for \(name) not found; calling the action directly")
                let shown = floors.shown(state), ids = state.building.floors.map(\.id)
                switch name {
                case "▲": floors.choice.step(1, from: shown, floors: ids)
                case "▼": floors.choice.step(-1, from: shown, floors: ids)
                default: floors.choice.resumeFollow()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                print("floor clicked \(name) → shown \(floors.shown(state)) · \(floors.choice)")
                step()
            }
        }
        step()
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
            // Bongo Cat: hover over the room, press and hold there (the centre, already clicked above), release,
            // then move (no click) up to the floor picker row, outside the room.
            if let container = host.superview {
                @MainActor func moved(_ p: CGPoint) {
                    container.mouseMoved(with: NSEvent.mouseEvent(with: .mouseMoved, location: windowPoint(p), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                                  windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!)
                }
                @MainActor func cursor(_ step: String) {
                    let bongo = NSCursor.current.image.size == NSSize(width: 32, height: 32)
                    print("cursor", step, "→", state.roomCursor.frame.map { "\($0)" } ?? "arrow", "· shown:", bongo ? "bongo" : (NSCursor.current == .arrow ? "arrow" : "other"))
                }
                moved(centre); cursor("over room")
                mouse(.leftMouseDown, centre); cursor("held")
                RunLoop.main.run(until: Date().addingTimeInterval(0.2)); cursor("held 0.2s")
                mouse(.leftMouseUp, centre); cursor("released")
                print("tap recorded (press and release without dragging):", zoom.tap != nil)
                moved(CGPoint(x: centre.x, y: zoom.roomRect.minY - 20)); cursor("outside room")
            }
            // The ? button (its recorded frame, nothing else): the help panel opens; the guide ships in the app.
            if HelpButton.frame.width > 0 {
                let f = HelpButton.frame, p = NSPoint(x: f.midX, y: window.contentView!.bounds.height - f.midY)
                for t in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    window.sendEvent(NSEvent.mouseEvent(with: t, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
                }
                RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                print("click ? → help panel shown:", state.helpShown, "· guide in app:", state.helpGuide.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
                state.helpShown = false
            } else {
                print("? button not found")
            }
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

/// `ClaudeBar --test-setup`: the setup window over temp folders only (a temp home with a mini Cat Office, an empty
/// claude folder, a temp bridge file, and an AppState over a temp projects.json), offscreen. Clicks only the recorded
/// targets setup-setup, setup-continue (Find) and setup-continue (Connect, with Patch and Start unticked first), and
/// prints the step and chosen folder after each, then the results, the temp statusLine and the setup state.
@MainActor
enum TestSetup {
    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--test-setup") else { return false }
        setvbuf(stdout, nil, _IOLBF, 0)
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("claudebar-setup-test-\(UUID().uuidString)").resolvingSymlinksInPath()
        let home = root.appendingPathComponent("home")
        let office = home.appendingPathComponent("Documents/projects/cat-office")
        let claude = home.appendingPathComponent(".claude")
        try? fm.createDirectory(at: office.appendingPathComponent("server/agent-bridge"), withIntermediateDirectories: true)
        try? fm.createDirectory(at: claude, withIntermediateDirectories: true)
        try? Data(#"{"name":"cat-office"}"#.utf8).write(to: office.appendingPathComponent("package.json"))
        var env = SetupEnvironment(home: home, claudeDir: claude, resources: SetupEnvironment.real.resources,
                                   bridgeFile: root.appendingPathComponent("bridge.json"))
    env.answers = { _ in false }   // never probe the real Cat Office
        let configFile = root.appendingPathComponent("projects.json")
        let state = AppState(config: ConfigStore(file: configFile))
        state.sideEffects = false
        print("temp root:", root.path)
        print("config:", state.config.file.path)

        SetupWindow.shared.open(state: state, env: env, offscreen: true)
        guard let model = SetupWindow.shared.model,
              let window = NSApp.windows.first(where: { $0.title == "Set up ClaudeBar" }) else { print("setup window didn't open"); exit(1) }
        // Never hang: the run is over in a few seconds.
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { print("timed out at step \(model.step)"); exit(1) }

        func report(_ after: String) {
            print("after \(after): step \(model.step) · chosen \(model.chosen ?? "none")")
        }
        /// Clicks the recorded target `id` (nothing else); false when it isn't on screen or something else is under it.
        func click(_ id: String) -> Bool {
            guard let frame = SetupTargets.frames[id], let content = window.contentView else { print("target \(id) not found"); return false }
            // SwiftUI's .global here is the whole window (title bar included), from its top-left.
            let target = NSRect(x: frame.minX, y: window.frame.height - frame.maxY, width: frame.width, height: frame.height)
            let point = NSPoint(x: target.midX, y: target.midY)
            guard let frameView = content.superview else { print("setup window has no frame view"); exit(1) }
            guard let hit = content.hitTest(frameView.convert(point, from: nil)) else { print("nothing under \(id)"); return false }
            let hitFrame = hit.convert(hit.bounds, to: nil)
            // Never click something else: the control under the point must be the recorded one.
            guard abs(hitFrame.midX - target.midX) < 4, abs(hitFrame.midY - target.midY) < 4 else {
                print("refusing to click \(id): \(type(of: hit)) at \(hitFrame) isn't the target at \(target)"); return false
            }
            print("click \(id) at window \(point) (hits \(type(of: hit)))")
            // Queue the mouse-up first: a native button tracks a press by reading it from the event queue.
            NSApp.postEvent(NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!, atStart: false)
            window.sendEvent(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
            return true
        }
        /// Waits (polling, up to 8s) for `done`, then runs `then`.
        func when(_ done: @escaping @MainActor () -> Bool, _ then: @escaping @MainActor () -> Void) {
            let deadline = Date().addingTimeInterval(8)
            func poll() {
                if done() { then(); return }
                guard Date() < deadline else { print("gave up waiting at step \(model.step)"); exit(1) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { MainActor.assumeIsolated { poll() } }
            }
            poll()
        }

        print("start: step \(model.step)")
        when({ SetupTargets.frames["setup-setup"] != nil }) {
            guard click("setup-setup") else { exit(1) }
            when({ model.step == .find && !model.searching && SetupTargets.frames["setup-continue"] != nil }) {
                report("setup-setup")
                guard click("setup-continue") else { exit(1) }
                when({ model.step == .connect }) {
                    report("setup-continue (Find)")
                    model.patch = false
                    model.start = false
                    print("on Connect: patch \(model.patch) · usage \(model.usage) · start \(model.start)")
                    // Let the window redraw (and re-record Continue) before clicking it.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { MainActor.assumeIsolated {
                        guard click("setup-continue") else { exit(1) }
                        when({ model.step == .done && !model.working }) {
                            report("setup-continue (Connect)")
                            for key in model.results.keys.sorted() {
                                let r = model.results[key]!
                                print("result \(key): \(r.ok ? "✓" : "✗") \(r.text)")
                            }
                            let settings = (try? Data(contentsOf: claude.appendingPathComponent("settings.json")))
                                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                            print("temp settings.json statusLine:", settings?["statusLine"].map { "\($0)" } ?? "none")
                            print("setup state:", state.settings.setup.state?.rawValue ?? "nil", "· seen:", state.settings.setup.seen,
                                  "· catOffice.dir:", state.settings.catOffice.dir ?? "nil")
                            print("chosen is the temp Cat Office:", model.chosen == office.path)
                            exit(0)
                        }
                    } }
                }
            }
        }
        return true
    }
}

/// `ClaudeBar --test-undo`: the undo window over a temp home only (ClaudeBar's status line installed there with a
/// record, and ClaudeBar's four folders), offscreen. Clicks only the recorded target undo-run, then prints the results,
/// the temp statusLine, and which temp folders are left. "Also remove" stays unticked, so all four must remain.
@MainActor
enum TestUndo {
    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--test-undo") else { return false }
        setvbuf(stdout, nil, _IOLBF, 0)
        let (env, root) = undoEnvironment()
        let fm = FileManager.default
        try? Data(#"{"model":"opus"}"#.utf8).write(to: env.claudeDir.appendingPathComponent("settings.json"))
        do { try SetupActions.statusLine(env: env).useClaudeBar() } catch { print("couldn't install the temp status line: \(error)"); exit(1) }
        let removal = ClaudeBarRemoval(home: env.home)
        for f in removal.folders { try? fm.createDirectory(at: f, withIntermediateDirectories: true) }
        let state = AppState(config: ConfigStore(file: root.appendingPathComponent("projects.json")))
        state.sideEffects = false
        print("temp root:", root.path)

        UndoWindow.shared.open(state: state, env: env, offscreen: true)
        guard let model = UndoWindow.shared.model,
              let window = NSApp.windows.first(where: { $0.title == UndoText.title }) else { print("undo window didn't open"); exit(1) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { print("timed out in phase \(model.phase)"); exit(1) }

        func click(_ id: String) -> Bool {
            guard let frame = SetupTargets.frames[id], let content = window.contentView else { print("target \(id) not found"); return false }
            let target = NSRect(x: frame.minX, y: window.frame.height - frame.maxY, width: frame.width, height: frame.height)
            let point = NSPoint(x: target.midX, y: target.midY)
            guard let frameView = content.superview else { print("undo window has no frame view"); exit(1) }
            guard let hit = content.hitTest(frameView.convert(point, from: nil)) else { print("nothing under \(id)"); return false }
            let hitFrame = hit.convert(hit.bounds, to: nil)
            guard abs(hitFrame.midX - target.midX) < 4, abs(hitFrame.midY - target.midY) < 4 else {
                print("refusing to click \(id): \(type(of: hit)) at \(hitFrame) isn't the target at \(target)"); return false
            }
            print("click \(id) at window \(point) (hits \(type(of: hit)))")
            NSApp.postEvent(NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!, atStart: false)
            window.sendEvent(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
            return true
        }
        func when(_ done: @escaping @MainActor () -> Bool, _ then: @escaping @MainActor () -> Void) {
            let deadline = Date().addingTimeInterval(8)
            func poll() {
                if done() { then(); return }
                guard Date() < deadline else { print("gave up waiting in phase \(model.phase)"); exit(1) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { MainActor.assumeIsolated { poll() } }
            }
            poll()
        }

        func fail(_ reason: String) -> Never { print("FAIL: \(reason)"); exit(1) }
        when({ model.phase == .choose && SetupTargets.frames["undo-run"] != nil }) {
            print("rows:", model.rows.map { "\($0.kind.rawValue)\($0.available ? "" : "(greyed)")" }.joined(separator: ", "),
                  "· ticked:", model.ticked.map(\.rawValue).sorted().joined(separator: ", "))
            if model.rows.contains(where: { $0.kind == .unpatch }) { fail("an unpatch row showed up (never clicked)") }
            if model.ticked != [.statusLine] { fail("ticked before the click was \(model.ticked.map(\.rawValue).sorted()), not [statusLine]") }
            guard click("undo-run") else { fail("couldn't click undo-run") }
            when({ model.phase == .done && !model.working }) {
                for kind in UndoRow.Kind.allCases { if let r = model.results[kind] { print("result \(kind.rawValue): \(r.ok ? "✓" : "✗") \(r.text)") } }
                print("done lines:", model.doneLines.joined(separator: " | "))
                let settings = (try? Data(contentsOf: env.claudeDir.appendingPathComponent("settings.json")))
                    .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                print("temp settings.json statusLine:", settings?["statusLine"].map { "\($0)" } ?? "none")
                let left = removal.folders.filter { fm.fileExists(atPath: $0.path) }.count
                print("temp folders left:", left, "of 4")
                if Set(model.results.keys) != [.statusLine] { fail("results were for \(model.results.keys.map(\.rawValue).sorted())") }
                if model.results[.statusLine]?.ok != true { fail("status line restore didn't succeed") }
                // The temp home had no status line before ClaudeBar's: say it's off, never that an old one is back.
                if model.results[.statusLine]?.text != StatusLineRestore.removed.message { fail("status line result text was wrong") }
                guard let settings else { fail("temp settings.json is unreadable") }
                if settings["statusLine"] != nil { fail("temp settings.json still has a statusLine") }
                if settings["model"] as? String != "opus" { fail("temp settings.json lost model") }
                if left != 4 { fail("only \(left) of 4 temp folders are left") }
                print("PASS")
                exit(0)
            }
        }
        return true
    }
}

/// `ClaudeBar --render-routes <floorId> <out.png>` (debug only): the floor's built room at the dropdown's room size,
/// with the WalkRouter routes of real walks drawn over it: from the elevator door spot to every desk and every Lounge
/// seat, in the view points the walking cats use (state.navs / state.rooms and the SceneFit FloorScene reports).
/// Routes are cyan polylines with a dot per waypoint; a walk that fell back to the L (no grid, no route) is orange.
/// Blocked grid cells are tinted red. Prints each walk's waypoints and any samples of its legs on blocked cells.
@MainActor
enum RenderRoutes {
    static func runIfRequested(state: AppState) -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-routes"), i + 2 < args.count else { return false }
        guard let floorId = Int(args[i + 1]) else { print("--render-routes: floor id \(args[i + 1]) isn't a number"); exit(1) }
        let out = URL(fileURLWithPath: args[i + 2])
        // Wait for the live data and the built rooms, like the other renders.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            guard let room = state.rooms[floorId], let floor = state.building.floor(id: floorId) else {
                print("--render-routes: floor \(floorId) has no built room (floors: \(state.rooms.keys.sorted()))"); exit(1)
            }
            let catHeight = state.building.catHeight ?? BuiltRoom.defaultCatHeight
            // The dropdown's room size; CLAUDEBAR_ROUTES_SIZE=WxH draws it bigger for a closer look.
            let wh = (ProcessInfo.processInfo.environment["CLAUDEBAR_ROUTES_SIZE"] ?? "").split(separator: "x").compactMap { Double($0) }
            let size = wh.count == 2 ? CGSize(width: wh[0], height: wh[1]) : CGSize(width: DropdownLayout.contentWidth, height: OfficeRoomView.height)
            let view = RoutesView(room: room, floor: floor, grid: state.navs[floorId], catHeight: catHeight,
                                  k: size.width / DropdownLayout.contentWidth)
                .environmentObject(state).environmentObject(RoomZoom())
            let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
            host.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = host
            window.orderFrontRegardless()
            // Let the room's picture load (FloorScene's task) and the fit arrive before capturing.
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: out)
                exit(0)
            }
        }
        return true
    }
}

/// The room with its routes over it (RenderRoutes).
private struct RoutesView: View {
    let room: BuiltRoom
    let floor: Floor
    let grid: NavGrid?
    let catHeight: Double
    /// Line and dot size factor (1 at the dropdown's room size).
    let k: CGFloat
    @State private var fit: SceneFit?

    /// A walk, with its ends' floor points (a raised seat's drawn feet are lifted off them).
    struct Walk { let name: String; let path: WalkPath; let routed: Bool; let fromFloor: FloorPoint; let toFloor: FloorPoint }

    var body: some View {
        ZStack(alignment: .topLeading) {
            FloorScene(room: room, floor: floor, catHeight: catHeight, cast: nil)
            if let fit {
                let walks = Self.walks(room: room, grid: grid, fit: fit)
                Canvas { ctx, _ in draw(&ctx, fit: fit, walks: walks) }
                .allowsHitTesting(false)
                .task { Self.log(room: room, grid: grid, fit: fit, walks: walks) }
            }
        }
        .coordinateSpace(name: "roomContent")
        .onPreferenceChange(SceneFitKey.self) { fit = $0[room.floorId] ?? fit }
    }

    private func draw(_ ctx: inout GraphicsContext, fit: SceneFit, walks: [Walk]) {
        if let grid {
            let n = Double(grid.size)
            for ui in 0..<grid.size { for vi in 0..<grid.size where !grid.isOpen(ui, vi) {
                let c = [(ui, vi), (ui + 1, vi), (ui + 1, vi + 1), (ui, vi + 1)].map {
                    fit.point(room.frame.px(FloorPoint(u: Double($0.0) / n, v: Double($0.1) / n)))
                }
                var cell = Path(); cell.addLines(c); cell.closeSubpath()
                ctx.fill(cell, with: .color(.red.opacity(0.4)))
            } }
        }
        for walk in walks {
            let color: Color = walk.routed ? .cyan : .orange
            var line = Path(); line.addLines(walk.path.points)
            ctx.stroke(line, with: .color(color), lineWidth: 1.2 * k)
            for p in walk.path.points {
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1.6 * k, y: p.y - 1.6 * k, width: 3.2 * k, height: 3.2 * k)), with: .color(color))
            }
            if let end = walk.path.points.last {
                ctx.stroke(Path(ellipseIn: CGRect(x: end.x - 3 * k, y: end.y - 3 * k, width: 6 * k, height: 6 * k)), with: .color(.yellow), lineWidth: k)
            }
        }
        if let start = walks.first?.path.points.first {
            ctx.fill(Path(ellipseIn: CGRect(x: start.x - 3.5 * k, y: start.y - 3.5 * k, width: 7 * k, height: 7 * k)), with: .color(.green))
        }
    }

    /// The walks a cat would take out of the elevator: to every desk's stand-at, and to every Lounge seat, with the
    /// inputs the peek gives WalkRouter: each end's drawn feet (a seat's lifted the way SceneCats draws them) and its
    /// floor point (CatFeet.floor; the elevator spot's for the start).
    static func walks(room: BuiltRoom, grid: NavGrid?, fit: SceneFit) -> [Walk] {
        let door = room.elevator?.standAt ?? FloorPoint(u: 0.5, v: 0.5)
        let fromFloor = ElevatorTrip.waitingPlace(door, index: 0)
        let from = fit.point(room.frame.px(fromFloor))
        var targets: [(String, CGPoint, FloorPoint)] = room.desks.map { ("desk \($0.id)", fit.point(room.frame.px($0.standAt)), $0.standAt) }
        for s in room.seats {
            let g = fit.point(room.frame.px(s.standAt))
            targets.append(("seat \(s.id) (lift \(s.lift))", CGPoint(x: g.x, y: g.y - CGFloat(s.lift) * fit.scale), s.standAt))
        }
        return targets.map { name, to, toFloor in
            let path = WalkRouter.path(from: from, fromFloor: fromFloor, to: to, toFloor: toFloor, grid: grid, frame: room.frame, fit: fit)
            return Walk(name: name, path: path, routed: grid != nil && path != WalkPath(from: from, to: to), fromFloor: fromFloor, toFloor: toFloor)
        }
    }

    static func log(room: BuiltRoom, grid: NavGrid?, fit: SceneFit, walks: [Walk]) {
        let blockedCells = grid.map { g in (0..<(g.size * g.size)).filter { !g.isOpen($0 / g.size, $0 % g.size) }.count } ?? 0
        print("floor \(room.floorId): \(grid.map { "grid \($0.size)×\($0.size), \(blockedCells) blocked cells" } ?? "NO GRID: every walk is the L (orange)"), fit scale \(fit.scale)")
        for w in walks {
            // In floor terms the drawn ends are their floor points (the hop up or down a lift is no floor move).
            var uv = w.path.points.map { room.frame.uv(fit.world($0)) }
            uv[0] = w.fromFloor
            uv[uv.count - 1] = w.toFloor
            let p = w.path.points
            let hop = p.count >= 2 ? String(format: ", last hop dx %.2f dy %.2f", p[p.count - 1].x - p[p.count - 2].x, p[p.count - 1].y - p[p.count - 2].y) : ""
            var blocked: [String] = []
            if let grid {
                // The hop up or down a lift is no floor move (a ≈ b): not sampled.
                for (k, (a, b)) in zip(uv, uv.dropFirst()).enumerated() where abs(b.u - a.u) > 1e-6 || abs(b.v - a.v) > 1e-6 {
                    let hits = (1..<20).filter { t in
                        let f = Double(t) / 20
                        return !grid.isOpenAt(FloorPoint(u: a.u + (b.u - a.u) * f, v: a.v + (b.v - a.v) * f))
                    }.count
                    if hits > 0 { blocked.append("leg \(k + 1)/\(uv.count - 1): \(hits)/19") }
                }
            }
            let diagonal = zip(uv, uv.dropFirst()).contains { a, b in abs(b.u - a.u) > 1e-6 && abs(b.v - a.v) > 1e-6 }
            let end = uv.last.map { String(format: "(%.3f, %.3f) %@", $0.u, $0.v, grid?.isOpenAt($0) == true ? "open" : "blocked") } ?? "-"
            print("  \(w.name): \(w.routed ? "route" : "L fallback"), \(w.path.points.count) points, ends \(end)"
                  + hop + (diagonal ? ", HAS A DIAGONAL LEG" : "") + (blocked.isEmpty ? "" : ", samples on blocked cells: " + blocked.joined(separator: "; ")))
        }
        fflush(stdout)
    }
}
