import AppKit
import ClaudeBarCore
import SwiftUI

/// `ClaudeBar --render-peek <out.png> [x,y]`: draws the office peek offscreen with live data (and the pointer
/// at x,y if given), saves it as a PNG and quits. For checking the layout without a screen.
@MainActor
enum RenderPeek {
    static func runIfRequested(state: AppState) -> Bool {
        if RenderLabel.runIfRequested(state: state) { return true }
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
        let host = NSHostingView(rootView: OfficePeekView().environmentObject(state).environmentObject(pointer)
            .background(Color(white: 0.16)).environment(\.colorScheme, .dark))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(white: 0.16, alpha: 1) // what the dark popover looks like
        window.contentView = host
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: out)
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
    let host = NSHostingView(rootView: view.background(Color(white: 0.16)).environment(\.colorScheme, .dark))
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
