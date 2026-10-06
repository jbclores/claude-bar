import ClaudeBarCore
import SwiftUI

/// A 10-segment bar like the status line's, colored by usage level.
struct UsageBar: View {
    let percent: Double?
    var segmentWidth: CGFloat = 7

    var body: some View {
        let filled = min(10, max(0, Int(((percent ?? 0) / 10).rounded())))
        let color = Theme.color(UsageLevel(percent: percent ?? 0))
        HStack(spacing: 2) {
            ForEach(0..<10, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i < filled ? color : Color.secondary.opacity(0.25))
                    .frame(width: segmentWidth, height: 8)
            }
        }
    }
}
