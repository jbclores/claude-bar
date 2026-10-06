import AppKit
import ClaudeBarCore
import SwiftUI

enum Theme {
    // Cat Office's status colors (dark theme).
    static let working = Color(hex: 0x45C486)
    static let waiting = Color(hex: 0xF2B53A)
    static let idle = Color(hex: 0x6F7A86)
    static let ended = Color(hex: 0x6AA5FF)

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
