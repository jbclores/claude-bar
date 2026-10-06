import AppKit
import SwiftUI

/// `ClaudeBar --render-peek <out.png> [x,y]`: draws the office peek offscreen with live data (and the pointer
/// at x,y if given), saves it as a PNG and quits. For checking the layout without a screen.
@MainActor
enum RenderPeek {
    static func runIfRequested(state: AppState) -> Bool {
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
