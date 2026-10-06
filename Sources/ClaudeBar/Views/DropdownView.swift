import AppKit
import ClaudeBarCore
import SwiftUI

struct DropdownView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            UsageHeader(usage: state.output.usage)
            Divider()
            Text("Projects").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if let error = state.configError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(Theme.waiting)
            }
            if state.output.projects.isEmpty {
                Button("No projects yet — Add Folder…") { chooseFolders() }.buttonStyle(.link)
            } else {
                ForEach(state.output.projects) { row in
                    ProjectRowView(row: row,
                                   onOpen: { NSWorkspace.shared.open(URL(fileURLWithPath: row.path)) },
                                   onRemove: { state.remove(row) })
                }
            }
            Divider()
            OfficeSectionView(rows: state.output.office, hindered: state.output.claudeHindered,
                              openOffice: { state.openCatOffice() })
            Divider()
            HStack(spacing: 14) {
                Button("Add Folder…") { chooseFolders() }
                Button("Edit Config") { state.editConfig() }
                Button("Open Cat Office ↗") { state.openCatOffice() }
                Toggle("Launch at Login", isOn: Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) }))
                    .toggleStyle(.checkbox)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .padding(14)
        .frame(width: 440)
    }

    private func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { state.addFolders(panel.urls) }
    }
}

struct UsageHeader: View {
    let usage: UsageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Usage").font(.headline)
                Spacer()
                if let asOf = usage.asOf {
                    Text("as of \(Format.age(asOf, now: Date()))").font(.caption).foregroundStyle(.secondary)
                }
            }
            row("5h", usage.fiveHourPct, usage.fiveHourResetsAt,
                extra: usage.workingCount > 0 ? "\(usage.workingCount) working" : nil)
            row("7d", usage.sevenDayPct, usage.sevenDayResetsAt, extra: nil)
        }
    }

    private func row(_ label: String, _ pct: Double?, _ resets: Date?, extra: String?) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.caption.monospaced()).frame(width: 20, alignment: .leading)
            UsageBar(percent: pct)
            Text(pct.map(Format.percent) ?? "—").font(.caption.monospacedDigit()).frame(width: 36, alignment: .trailing)
            if let extra { Text(extra).font(.caption).foregroundStyle(Theme.working) }
            Spacer()
            if let resets { Text(Format.resets(resets, now: Date())).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct ProjectRowView: View {
    let row: ProjectRow
    let onOpen: () -> Void
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            dot.padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.name).font(.body.weight(.medium)).lineLimit(1)
                    if case .live(let status, _) = row.state {
                        Text(row.needsAttention && status != .waiting ? "your turn" : status.rawValue)
                            .font(.caption).foregroundStyle(row.needsAttention ? Theme.waiting : Theme.color(status))
                    }
                    Spacer()
                    trailing.font(.caption).foregroundStyle(.secondary)
                    if hovering {
                        Button(action: onRemove) { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove from list")
                    }
                }
                detail.font(.caption).foregroundStyle(.secondary)
            }
        }
        .opacity(isDimmed ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { hovering = $0 }
        .help(row.path)
    }

    private var isDimmed: Bool {
        if case .stale = row.state { return true }
        return false
    }

    @ViewBuilder private var dot: some View {
        switch row.state {
        case .live(let status, _):
            Circle().fill(row.needsAttention ? Theme.waiting : Theme.color(status)).frame(width: 8, height: 8)
        case .missing:
            Circle().strokeBorder(Color.red, lineWidth: 1.5).frame(width: 8, height: 8)
        default:
            Circle().strokeBorder(Color.secondary, lineWidth: 1.5).frame(width: 8, height: 8)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch row.state {
        case .live(_, let count) where count >= 2: Text("×\(count)")
        case .stale(let since): Text(Format.age(since, now: Date()))
        default: EmptyView()
        }
    }

    @ViewBuilder private var detail: some View {
        switch row.state {
        case .missing:
            Text("missing")
        case .noSessions:
            Text([row.branch, "no sessions yet"].compactMap { $0 }.joined(separator: " · "))
        default:
            HStack(spacing: 6) {
                Text([row.branch, row.model].compactMap { $0 }.joined(separator: " · ")).lineLimit(1)
                if let ctx = row.contextPct {
                    Text("· ctx")
                    UsageBar(percent: ctx, segmentWidth: 5)
                    Text(Format.percent(ctx)).monospacedDigit()
                }
            }
        }
    }
}
