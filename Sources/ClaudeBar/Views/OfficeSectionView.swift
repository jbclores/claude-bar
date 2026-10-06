import ClaudeBarCore
import SwiftUI

/// The office cats, one row each: status, how long, where and what.
struct OfficeCatList: View {
    let rows: [OfficeRow]
    let openOffice: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if rows.isEmpty {
                Text("No office cats right now").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(rows) { row in
                HStack(spacing: 8) {
                    Circle().fill(row.needsAttention ? Theme.waiting : Theme.color(row.status)).frame(width: 7, height: 7)
                    Text(row.label).font(.callout.weight(.medium)).lineLimit(1).layoutPriority(1)
                    Text(statusText(row)).font(.caption)
                        .foregroundStyle(row.needsAttention ? Theme.waiting : Theme.color(row.status))
                        .fixedSize()
                    Spacer(minLength: 8)
                    Text(row.lastAction ?? row.branch ?? "")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: openOffice)
                .help([row.name, row.detail].compactMap { $0 }.joined(separator: " — "))
            }
        }
    }

    private func statusText(_ row: OfficeRow) -> String {
        Format.statusText(row.status, needsYou: row.needsAttention || row.status == .waiting, since: row.since)
    }
}

/// Shown while Cat Office is offline: a Start button, "Starting…", or why it failed.
struct OfficeStarter: View {
    let launch: OfficeLaunch
    let start: () -> Void
    let openLog: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            switch launch {
            case .none:
                Button("Start Cat Office", action: start)
            case .starting:
                ProgressView().controlSize(.small)
                Text("Starting Cat Office…").font(.caption).foregroundStyle(.secondary)
            case .failed(let message):
                Text(message).font(.caption).foregroundStyle(Theme.waiting)
                Button("Try Again", action: start).buttonStyle(.link).font(.caption)
                Button("Open Log", action: openLog).buttonStyle(.link).font(.caption)
            }
        }
    }
}
