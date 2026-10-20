import ClaudeBarCore
import SwiftUI

/// A 10-segment bar like the status line's, colored by usage level. Each segment fills in proportion (10% a
/// segment), and any use at all shows at least a sliver, so 1% doesn't read as empty.
struct UsageBar: View {
    let percent: Double?
    var segmentWidth: CGFloat = 7

    var body: some View {
        let pct = min(100, max(0, percent ?? 0))
        let color = Theme.color(UsageLevel(percent: pct))
        HStack(spacing: 2) {
            ForEach(0..<10, id: \.self) { i in
                let width = Self.fill(segment: i, percent: pct, width: segmentWidth)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.secondary.opacity(0.25))
                    .overlay(alignment: .leading) {
                        if width > 0 { RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: width) }
                    }
                    .frame(width: segmentWidth, height: 8)
            }
        }
    }

    /// How much of segment `i` is filled: its share of `percent`, with a 2-point sliver for the first one's smallest use.
    static func fill(segment i: Int, percent: Double, width: CGFloat) -> CGFloat {
        let share = min(1, max(0, (percent - Double(i) * 10) / 10))
        guard share > 0 else { return 0 }
        return i == 0 ? max(2, width * share) : width * share
    }
}
