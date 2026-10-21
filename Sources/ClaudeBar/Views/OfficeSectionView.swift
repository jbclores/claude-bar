import ClaudeBarCore
import SwiftUI

/// The office cats, one row each: status, how long, where and what; a waiting one's prompt and answer buttons
/// unfolded under it. A row click opens Cat Office on that cat.
struct OfficeCatList: View {
    let rows: [OfficeRow]
    @EnvironmentObject var state: AppState

    private func agent(_ row: OfficeRow) -> OfficeAgent? { state.office?.agents.first { $0.key == row.id } }

    private func open(_ row: OfficeRow) {
        if let agent = agent(row) { state.openInCatOffice(agent) } else { state.openCatOffice() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if rows.isEmpty {
                Text("No office cats right now").font(.caption).foregroundStyle(Theme.secondaryText)
            }
            // At most 5 rows (one that needs you always among them); the rest in Cat Office.
            let cut = OfficeRow.shown(rows, max: 5)
            ForEach(cut.rows) { row in
                rowView(row)
                if let agent = agent(row), AnswerPanel.shows(agent) {
                    // Under the title: past the dot (and a helper's ↳).
                    AnswerPanel(agent: agent, targetPrefix: "answer")
                        .padding(.leading, row.isSubagent ? 37 : 15)
                        .padding(.bottom, 4)
                }
            }
            if cut.more > 0 {
                Button("+\(cut.more) more in Cat Office") { state.openCatOffice() }
                    .buttonStyle(.link).font(.caption).padding(.leading, 15)
            }
        }
    }

    private func rowView(_ row: OfficeRow) -> some View {
        // On the first line's baseline, so the dot stays by the project when a task line sits underneath.
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if row.isSubagent {
                // A helper its parent started, listed under it.
                Text("↳").font(.caption).foregroundStyle(Theme.secondaryText).padding(.leading, 10)
            }
            Circle().fill(row.needsAttention ? Theme.waiting : Theme.color(row.status)).frame(width: 7, height: 7)
                .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 4 }
            if row.isSubagent, let type = row.agentType {
                Text(type).font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText).lineLimit(1).fixedSize()
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            if row.isSubagent {
                Text(row.label).font(.caption.weight(.medium)).lineLimit(1).layoutPriority(1)
                status(row)
            } else {
                // The project names the row; what tells it apart (task, first prompt, branch) sits underneath.
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 8) {
                        Text(row.place).font(.callout.weight(.medium)).lineLimit(1).layoutPriority(1)
                        status(row)
                    }
                    if let subtitle = row.subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 8)
            // While it runs, what it's doing in two or three words; the file or program, and the raw action, are on hover.
            if row.status == .working, let action = row.lastAction {
                Text(ActionSummary.short(action, working: true))
                    .font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1).fixedSize()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { open(row) }
        .help(([row.name, row.lastAction.map { ActionSummary.calm($0, working: row.status == .working) }, row.detail]
            + [row.lastAction == row.detail ? nil : row.lastAction])
            .compactMap { $0 }.joined(separator: "\n"))
    }

    private func status(_ row: OfficeRow) -> some View {
        Text(statusText(row)).font(.caption)
            .foregroundStyle(row.needsAttention ? Theme.waitingText : Theme.color(row.status))
            .fixedSize()
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
                Text("Starting Cat Office…").font(.caption).foregroundStyle(Theme.secondaryText)
            case .failed(let message):
                Text(message).font(.caption).foregroundStyle(Theme.waitingText)
                Button("Try again", action: start).buttonStyle(.link).font(.caption)
                Button("Open log", action: openLog).buttonStyle(.link).font(.caption)
            }
        }
    }
}
