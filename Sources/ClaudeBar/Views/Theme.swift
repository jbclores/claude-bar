import AppKit
import ClaudeBarCore
import SwiftUI

enum Theme {
    // Cat Office's status colors (dark theme).
    static let working = Color(hex: 0x45C486)
    static let waiting = Color(hex: 0xF2B53A)
    static let idle = Color(hex: 0x6F7A86)
    static let ended = Color(hex: 0x6AA5FF)
    /// Amber as text: the same in dark mode, a deeper amber on the light popover where the bright one fades.
    static let waitingText = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0xF2 / 255, green: 0xB5 / 255, blue: 0x3A / 255, alpha: 1)
            : NSColor(srgbRed: 0xA8 / 255, green: 0x6A / 255, blue: 0x00 / 255, alpha: 1)
    })
    /// Secondary text: a step darker than the system's, which faded on the light popover's grey.
    static let secondaryText = Color.primary.opacity(0.68)

    static func color(_ status: AgentStatus) -> Color {
        switch status {
        case .working: working
        case .waiting: waiting
        case .idle: idle
        case .ended: ended
        }
    }

    static func color(_ level: UsageLevel) -> Color {
        switch level {
        case .ok: Color(hex: 0x3FB950)
        case .warn: Color(hex: 0xD29922)
        case .high: Color(hex: 0xF85149)
        }
    }

    static func nsColor(_ level: UsageLevel) -> NSColor { NSColor(color(level)) }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
