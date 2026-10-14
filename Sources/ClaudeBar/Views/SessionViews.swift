import ClaudeBarCore
import SwiftUI

/// "Open in Cat Office" (on that agent's panel) and, when ClaudeBar can find it, "Show terminal".
struct JumpLinks: View {
    let agent: OfficeAgent
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 12) {
            Button("Open in Cat Office") { state.openInCatOffice(agent) }
                .help("Opens Cat Office on this session's panel")
            if state.canShowTerminal(agent) {
                Button("Show terminal") { state.showTerminal(agent) }
                    .help("Brings its Terminal or iTerm tab forward")
            }
            if state.terminalMissed.contains(agent.id) {
                Text("Couldn't bring it forward").foregroundStyle(Theme.secondaryText).lineLimit(1)
                    .help("The tab wasn't found, or ClaudeBar isn't allowed to control Terminal or iTerm "
                        + "(System Settings → Privacy & Security → Automation).")
            }
        }
        .buttonStyle(.link)
        .font(.caption)
    }
}

/// What a waiting session waits on (a permission, a question, a plan) and the buttons that answer it through Cat
/// Office; "Sent" after a click, or why it didn't go through. Nothing for other sessions.
struct AnswerPanel: View {
    let agent: OfficeAgent
    /// Click tests: records each button's frame as "<prefix>-<title>" (and "Sent" as "<prefix>-sent") in
    /// state.shortcutTargets.
    var targetPrefix: String?
    /// The jump links under "Sent" or an error (and "Open in Cat Office" for a plan); the hover card has its own below.
    var links = true
    @EnvironmentObject var state: AppState

    /// The agent waits on something ClaudeBar can show.
    static func shows(_ agent: OfficeAgent) -> Bool {
        agent.status == .waiting && agent.pendingPrompt != nil && !agent.isSpare
    }

    var body: some View {
        if Self.shows(agent), let prompt = agent.pendingPrompt {
            let choices = AnswerChoices.of(prompt)
            VStack(alignment: .leading, spacing: 4) {
                Text(choices.prompt).font(.callout.weight(.semibold)).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = choices.detail {
                    Text(detail).font(isPermission(prompt) ? .caption.monospaced() : .caption)
                        .foregroundStyle(Theme.secondaryText).lineLimit(1).truncationMode(.middle)
                        .help(detail)
                }
                outcome(choices, prompt: prompt)
            }
        }
    }

    @ViewBuilder
    private func outcome(_ choices: AnswerChoices, prompt: PendingPrompt) -> some View {
        switch state.answerState[agent.id] {
        case .sent:
            Text("Sent").font(.caption.weight(.semibold)).foregroundStyle(Theme.working)
                .recordFrame(targetPrefix.map { "\($0)-sent" }, in: state.shortcutTargets)
            // In case the dialog didn't take it: the way there (the buttons come back if it still waits after a while).
            if links { JumpLinks(agent: agent) }
        case .sending:
            ProgressView().controlSize(.small)
        case .failed(let message):
            Text(message).font(.caption).foregroundStyle(Theme.waiting).fixedSize(horizontal: false, vertical: true)
            if links { JumpLinks(agent: agent) }
        case nil:
            if choices.buttons.isEmpty {
                Button("Answer in Cat Office") { state.openInCatOffice(agent) }.buttonStyle(.link).font(.caption)
            } else {
                FlowRow(spacing: 6) {
                    ForEach(Array(choices.buttons.enumerated()), id: \.offset) { i, button in
                        answerButton(button, first: i == 0)
                    }
                    if links, case .plan = prompt {
                        Button("Open in Cat Office") { state.openInCatOffice(agent) }.buttonStyle(.link).font(.caption)
                            .help("Read the whole plan in Cat Office")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func answerButton(_ button: AnswerButton, first: Bool) -> some View {
        let name = targetPrefix.map { "\($0)-\(button.title.lowercased().replacingOccurrences(of: " ", with: "-"))" }
        Group {
            if first {
                Button(button.title) { state.answer(agent, button) }.buttonStyle(.borderedProminent)
            } else {
                Button(button.title) { state.answer(agent, button) }.buttonStyle(.bordered)
            }
        }
        .controlSize(.small)
        .lineLimit(1)
        .help(button.help ?? "")
        .recordFrame(name, in: state.shortcutTargets)
    }

    private func isPermission(_ p: PendingPrompt) -> Bool {
        if case .permission = p { return true }
        return false
    }
}

/// "4 sessions finished · 2h 10m working · busiest: claude-bar" at the top of Projects; nothing on a quiet day.
struct TodayRecapLine: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if let line = state.todayRecap.line {
            Text(line).font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
        }
    }
}

/// Lays its views out left to right, starting a new line when one doesn't fit (answer buttons with long options).
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            for (index, x) in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + row.y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
            }
        }
    }

    private struct Row { var items: [(Int, CGFloat)] = []; var width: CGFloat = 0; var height: CGFloat = 0; var y: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if !row.items.isEmpty, row.width + spacing + size.width > width {
                rows.append(row)
                row = Row(y: row.y + row.height + spacing)
            }
            row.items.append((i, row.items.isEmpty ? 0 : row.width + spacing))
            row.width = row.items.count == 1 ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}

extension View {
    /// Records this view's frame in the window under `name` (nil: nothing), for the click tests.
    @ViewBuilder
    func recordFrame(_ name: String?, in targets: FloorSelection) -> some View {
        if let name { target(name, in: targets) } else { self }
    }
}
