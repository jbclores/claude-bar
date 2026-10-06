import ClaudeBarCore
import SwiftUI

struct OfficeSectionView: View {
    let rows: [OfficeRow]?
    let hindered: Bool
    let openOffice: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Office").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if rows == nil {
                    Text("Cat Office isn't running").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(hindered ? "Claude hindered" : "Claude OK").font(.caption)
                        .foregroundStyle(hindered ? Theme.waiting : .secondary)
                }
            }
            if let rows {
                if rows.isEmpty {
                    Text("No office cats right now").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(rows) { row in
                    HStack(spacing: 8) {
                        Circle().fill(row.needsAttention ? Theme.waiting : Theme.color(row.status)).frame(width: 7, height: 7)
                        Text(row.name).font(.callout.weight(.medium)).lineLimit(1)
                        Text(statusText(row)).font(.caption)
                            .foregroundStyle(row.needsAttention ? Theme.waiting : Theme.color(row.status))
                        Spacer(minLength: 8)
                        Text([row.place, row.detail ?? row.branch].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(perform: openOffice)
                    .help(row.detail ?? row.name)
                }
            }
        }
    }

    private func statusText(_ row: OfficeRow) -> String {
        let label = row.needsAttention && row.status == .idle ? "your turn" : row.status.rawValue
        guard let since = row.since else { return label }
        return "\(label) \(Format.duration(Date().timeIntervalSince(since)))"
    }
}
