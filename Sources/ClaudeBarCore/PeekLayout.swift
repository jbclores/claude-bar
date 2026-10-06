import Foundation

/// Who sits where in the tiny office: a row of desks (busy cats at theirs, a free desk for each cat out in the
/// lounge, up to `maxDesks` in all) and a lounge for idle cats.
public struct PeekLayout: Equatable, Sendable {
    public var desks: [OfficeAgent]
    public var deskOverflow: Int
    /// Desks shown empty: their cats are asleep in the lounge.
    public var freeDesks: Int
    public var lounge: [OfficeAgent]
    public var loungeOverflow: Int

    public static func make(_ agents: [OfficeAgent], maxDesks: Int = 3, maxLounge: Int = 5) -> PeekLayout {
        let shown = agents
            .filter { $0.status != .ended }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let busy = shown.filter { $0.status == .working || $0.status == .waiting }
        let idle = shown.filter { $0.status == .idle }
        let desks = Array(busy.prefix(maxDesks))
        return PeekLayout(desks: desks, deskOverflow: max(0, busy.count - maxDesks),
                          freeDesks: max(0, min(maxDesks, shown.count) - desks.count),
                          lounge: Array(idle.prefix(maxLounge)), loungeOverflow: max(0, idle.count - maxLounge))
    }
}

/// Cat Office's CSS motion, as offset and scale at a moment: typing bobs 1.5pt every 0.35s over a 3s breathe;
/// sleeping breathes over 4.8s; waiting stands still.
public struct CatMotion: Equatable, Sendable {
    public var offsetY: Double
    public var scale: Double

    public init(offsetY: Double, scale: Double) {
        self.offsetY = offsetY
        self.scale = scale
    }

    public static func at(status: AgentStatus, time: TimeInterval) -> CatMotion {
        switch status {
        case .working:
            CatMotion(offsetY: -1.5 * sin(2 * .pi * time / 0.35), scale: 1 + 0.015 * sin(2 * .pi * time / 3))
        case .idle:
            CatMotion(offsetY: 0, scale: 1 + 0.03 * sin(2 * .pi * time / 4.8))
        case .waiting, .ended:
            CatMotion(offsetY: 0, scale: 1)
        }
    }
}
