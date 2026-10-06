import AppKit
import ClaudeBarCore
import SwiftUI

enum DropdownTab: String, CaseIterable {
    case office, projects, settings

    var title: String {
        switch self {
        case .office: "Office"
        case .projects: "Projects"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .office: "cat.fill"
        case .projects: "folder"
        case .settings: "gearshape"
        }
    }
}

/// The click dropdown: usage always on top, then the Office / Projects / Settings tabs, then the footer.
struct DropdownView: View {
    @EnvironmentObject var state: AppState
    /// Reopens on the tab used last.
    @AppStorage("dropdownTab") private var storedTab: DropdownTab = .office
    /// Shows this tab without touching the remembered one (for --render-dropdown).
    var forcedTab: DropdownTab?

    private var tab: Binding<DropdownTab> {
        forcedTab.map { .constant($0) } ?? $storedTab
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            UsageHeader(usage: state.output.usage)
            TabBar(selected: tab, attention: state.needsAttention)
            if let error = state.configError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(Theme.waiting)
            }
            switch tab.wrappedValue {
            case .office: OfficeTabView()
            case .projects: ProjectsTabView()
            case .settings: SettingsTabView()
            }
            Divider()
            HStack(spacing: 14) {
                if state.office != nil {
                    Button("Open Cat Office ↗") { state.openCatOffice() }
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .padding(14)
        .frame(width: 500)
    }
}

/// Office · Projects · Settings, as pill buttons; an amber dot on Office when something needs the user.
struct TabBar: View {
    @Binding var selected: DropdownTab
    let attention: Bool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(DropdownTab.allCases, id: \.self) { tab in
                Button { selected = tab } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.symbol)
                        Text(tab.title)
                        if tab == .office && attention {
                            Circle().fill(Theme.waiting).frame(width: 6, height: 6)
                        }
                    }
                    .font(.callout.weight(tab == selected ? .semibold : .regular))
                    .foregroundStyle(tab == selected ? .primary : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(tab == selected ? Color.primary.opacity(0.12) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.05)))
    }
}

/// The tiny office (same drawing as the hover peek) and the cat list under it.
struct OfficeTabView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var pointer = PeekPointer()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let office = state.office { OfficeSummary(office: office).font(.caption) }
            OfficeRoomView()
            if let rows = state.output.office {
                OfficeCatList(rows: rows, openOffice: { state.openCatOffice() })
            }
        }
        .environmentObject(pointer)
        .coordinateSpace(name: "office")
        .onContinuousHover(coordinateSpace: .named("office")) { phase in
            switch phase {
            case .active(let point): pointer.location = point
            case .ended: pointer.location = nil
            }
        }
    }
}

struct ProjectsTabView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if state.output.projects.isEmpty {
                Text("No projects yet").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(state.output.projects) { row in
                ProjectRowView(row: row,
                               onOpen: { NSWorkspace.shared.open(URL(fileURLWithPath: row.path)) },
                               onRemove: { state.remove(row) })
            }
            Button { chooseFolders() } label: { Label("Add Folder…", systemImage: "plus") }
                .buttonStyle(.link)
                .font(.caption)
        }
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

struct SettingsTabView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            setting("Launch at Login", state.launchAtLogin) { state.setLaunchAtLogin($0) }
            setting("Notify when a cat finishes", state.settings.notifications) { state.setNotifications($0) }
            setting("Start Cat Office with ClaudeBar", state.settings.catOffice.autoStart) { state.setAutoStart($0) }
            setting("Show the office on hover", state.settings.hoverPeek) { state.setHoverPeek($0) }
            Divider()
            HStack(spacing: 14) {
                Button("Edit Config") { state.editConfig() }
                Button("Open Log") { state.openLauncherLog() }
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .font(.callout)
    }

    private func setting(_ title: String, _ value: Bool, _ change: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { value }, set: change)) {
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
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
