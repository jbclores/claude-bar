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

/// Which dropdown tab is showing; saved so the dropdown reopens on it.
@MainActor
final class TabSelection: ObservableObject {
    static let key = "dropdownTab"
    @Published var tab: DropdownTab {
        didSet { UserDefaults.standard.set(tab.rawValue, forKey: Self.key) }
    }

    init(_ tab: DropdownTab? = nil) {
        self.tab = tab ?? DropdownTab(rawValue: UserDefaults.standard.string(forKey: Self.key) ?? "") ?? .office
    }
}

/// Top of the dropdown: the ClaudeBar title with the theme switch, then usage, and a config error if there is one.
struct DropdownHeader: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TitleRow()
            UsageHeader(usage: state.output.usage)
            if let error = state.configError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(Theme.waiting)
            }
        }
        .frame(width: DropdownLayout.contentWidth, alignment: .leading)
    }
}

/// Under the tabs: the selected tab's content, then the footer.
struct DropdownBody: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var selection: TabSelection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch selection.tab {
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
        .frame(width: DropdownLayout.contentWidth, alignment: .leading)
    }
}

enum DropdownLayout {
    static let width: CGFloat = 500
    static let padding: CGFloat = 14
    static var contentWidth: CGFloat { width - padding * 2 }
}

/// The whole dropdown drawn by SwiftUI alone, for --render-dropdown images (the live dropdown is
/// DropdownController, whose tab control is AppKit so its clicks always arrive).
struct DropdownView: View {
    @EnvironmentObject var state: AppState
    var forcedTab: DropdownTab?

    var body: some View {
        let selection = TabSelection(forcedTab)
        return VStack(alignment: .leading, spacing: 10) {
            DropdownHeader()
            Picker("", selection: .constant(selection.tab)) {
                ForEach(DropdownTab.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            DropdownBody(selection: selection)
        }
        .padding(DropdownLayout.padding)
        .frame(width: DropdownLayout.width)
        .environmentObject(RoomZoom())
        .environmentObject(FloorSelection.forRender())
    }
}

/// The live dropdown: SwiftUI usage header, a native AppKit tab control, SwiftUI tab content. The tab control
/// sits outside SwiftUI on purpose: inside a hosting view its clicks were swallowed in the menu bar popover.
final class DropdownController: NSViewController {
    private let state: AppState
    private let selection = TabSelection()
    /// The dropdown is showing its Office tab (for the office's music); `onTabChange` reports switches.
    var showsOffice: Bool { selection.tab == .office }
    var onTabChange: (() -> Void)?
    let roomZoom = RoomZoom()
    let floorSelection = FloorSelection()
    private var header: ClickThroughHostingView<AnyView>!
    private var tabs: FirstClickSegmentedControl!
    private(set) var content: ClickThroughHostingView<AnyView>!

    init(state: AppState) {
        self.state = state
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        header = ClickThroughHostingView(rootView: AnyView(DropdownHeader().environmentObject(state)))
        content = ClickThroughHostingView(rootView: AnyView(DropdownBody(selection: selection).environmentObject(state).environmentObject(roomZoom).environmentObject(floorSelection)))
        tabs = FirstClickSegmentedControl(labels: DropdownTab.allCases.map(\.title), trackingMode: .selectOne,
                                          target: self, action: #selector(tabChanged(_:)))
        for (i, tab) in DropdownTab.allCases.enumerated() {
            tabs.setImage(NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title), forSegment: i)
            tabs.setImageScaling(.scaleProportionallyDown, forSegment: i)
        }
        tabs.controlSize = .large
        tabs.segmentDistribution = .fillEqually
        tabs.selectedSegment = DropdownTab.allCases.firstIndex(of: selection.tab) ?? 0

        // Each SwiftUI piece in a plain container: a hosting view claims clicks beyond its own frame when its
        // content draws outside it (the office's cats do), which took the tab control's clicks.
        let stack = NSStackView(views: [BoundedContainer(header), tabs, ZoomingContainer(content, zoom: roomZoom, cursor: state.roomCursor)])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: DropdownLayout.padding, left: DropdownLayout.padding,
                                        bottom: DropdownLayout.padding, right: DropdownLayout.padding)
        stack.translatesAutoresizingMaskIntoConstraints = false
        tabs.widthAnchor.constraint(equalToConstant: DropdownLayout.contentWidth).isActive = true
        for host in [header!, content!] {
            host.sizingOptions = [.intrinsicContentSize]
            // Keep each piece at its natural height: squeezed, its content spilled over the tabs and took their clicks.
            host.setContentHuggingPriority(.required, for: .vertical)
            host.setContentCompressionResistancePriority(.required, for: .vertical)
            host.onSizeChange = { [weak self] _ in self?.resize() }
        }
        tabs.setContentCompressionResistancePriority(.required, for: .vertical)
        view = stack
        resize()
    }

    /// The office shows the whole room each time the dropdown opens.
    func resetZoom() {
        roomZoom.reset()
        floorSelection.reopen()
    }

    /// "Office •" on the Office tab when something needs the user.
    func updateAttention(_ attention: Bool) {
        tabs?.setLabel(attention ? "Office •" : "Office", forSegment: 0)
    }

    @objc private func tabChanged(_ sender: NSSegmentedControl) {
        guard DropdownTab.allCases.indices.contains(sender.selectedSegment) else { return }
        selection.tab = DropdownTab.allCases[sender.selectedSegment]
        onTabChange?()
        // Measure once SwiftUI has laid out the new tab.
        DispatchQueue.main.async { [weak self] in self?.resize() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.resize() }
    }

    private func resize() {
        guard let header, let tabs, let content else { return }
        view.layoutSubtreeIfNeeded()
        let height = header.fittingSize.height + tabs.fittingSize.height + content.fittingSize.height
            + 10 * 2 + DropdownLayout.padding * 2
        let size = NSSize(width: DropdownLayout.width, height: height)
        if size.height > 0, size != preferredContentSize { preferredContentSize = size }
    }
}

/// The dropdown's tab control: takes the first click even while ClaudeBar isn't active.
final class FirstClickSegmentedControl: NSSegmentedControl {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The tiny office (same drawing as the hover peek) and the cat list under it.
struct OfficeTabView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var pointer = PeekPointer()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Known Cat Office: configured or last seen running (a folder that exists), or its feed is live.
            let known = CatOfficeDiscovery.folderToStart(configured: state.settings.catOffice.dir,
                                                         remembered: UserDefaults.standard.string(forKey: AppState.rememberedDirKey)) != nil
            if let card = state.settings.setup.card(catOfficeKnown: known || state.office != nil) {
                SetupCard(reduced: card == .reduced) { SetupWindow.shared.open(state: state) }
            }
            FloorPicker()
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

/// "Cat Office isn't set up yet · Set up…" (or, reduced: "Some extras are off · Fix…").
struct SetupCard: View {
    let reduced: Bool
    let open: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: reduced ? "exclamationmark.circle" : "pawprint").foregroundStyle(reduced ? Theme.waiting : .secondary)
            Text(reduced ? "Some extras are off" : "Cat Office isn't set up yet").font(.callout)
            Spacer()
            Button(reduced ? "Fix…" : "Set up…", action: open).buttonStyle(.link)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
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
    /// What "Restore my old status line" did (its error, or that it worked).
    @State private var restoreMessage: String?
    /// The two folded sections: the four separate sounds, and Advanced (Refresh office art, Edit Config, Open Log).
    @State private var soundsOpen = SettingsTabView.startOpen
    @State private var advancedOpen = SettingsTabView.startOpen
    /// Renders only: draw both folded sections open (`CLAUDEBAR_RENDER_SETTINGS_OPEN=1`).
    static var startOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            heading("General")
            setting("Launch at Login", state.launchAtLogin) { state.setLaunchAtLogin($0) }
            setting("Notify when a cat finishes", state.settings.notifications) { state.setNotifications($0) }
            setting("Start Cat Office with ClaudeBar", state.settings.catOffice.autoStart) { state.setAutoStart($0) }
            setting("Show the office on hover", state.settings.hoverPeek) { state.setHoverPeek($0) }
            setting("Show spare cats", state.settings.showSpareCats) { state.setShowSpareCats($0) }
                .help("Also draw the office's own cats (the ones with no Claude session)")
            Divider()
            sounds
            Divider()
            setup
            Divider()
            fold("Advanced", open: $advancedOpen)
            if advancedOpen {
                HStack(spacing: 14) {
                    Button("Refresh office art") { state.refreshArt() }
                        .help("Check Cat Office now for changed floors, furniture and characters")
                    Button("Edit Config") { state.editConfig() }
                    Button("Open Log") { state.openLauncherLog() }
                }
                .buttonStyle(.link)
                .font(.caption)
                .padding(.leading, 16)
            }
        }
        .font(.callout)
    }

    /// One "Cat sounds" switch; with it on, the volume and the four separate sounds (folded).
    @ViewBuilder private var sounds: some View {
        let s = state.settings.sounds
        heading("Sounds")
        setting("Cat sounds", s.on) { state.setSound("on", $0) }
        if s.on {
            HStack(spacing: 8) {
                Text("Volume")
                Image(systemName: "speaker.fill").font(.caption).foregroundStyle(.secondary)
                Slider(value: Binding(get: { state.settings.sounds.volume }, set: { state.setSoundVolume($0) }),
                       in: 0...1) { editing in if !editing { state.previewSound() } }
                    .controlSize(.small)
                Image(systemName: "speaker.wave.3.fill").font(.caption).foregroundStyle(.secondary)
            }
            fold("Choose sounds", note: "\(s.chosenCount) of \(SoundSettings.chosenTotal) on", open: $soundsOpen)
            if soundsOpen {
                VStack(alignment: .leading, spacing: 9) {
                    setting("Meow when a cat needs you", s.needsYou) { state.setSound("needsYou", $0) }
                    setting("Purr when a cat finishes", s.finished) { state.setSound("finished", $0) }
                    setting("Meow when I click a cat", s.click) { state.setSound("click", $0) }
                    setting("Ding when a cat rides the elevator", s.elevator) { state.setSound("elevator", $0) }
                }
                .padding(.leading, 16)
            }
        }
    }

    /// "✓ Set up · Cat Office: <name>" (full path on hover), then "Set up ClaudeBar…" and "Undo ClaudeBar's changes…".
    @ViewBuilder private var setup: some View {
        let setup = state.settings.setup
        let running = UserDefaults.standard.string(forKey: AppState.rememberedDirKey)
        heading("Setup")
        HStack(spacing: 4) {
            if setup.state == .full {
                Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Theme.working)
            }
            Text(setup.line(catOfficeDir: state.settings.catOffice.dir, runningDir: running, home: NSHomeDirectory()))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
        .help(SetupSettings.folderPath(catOfficeDir: state.settings.catOffice.dir, runningDir: running,
                                       home: NSHomeDirectory()) ?? "")
        HStack(spacing: 14) {
            Button("Set up ClaudeBar…") { SetupWindow.shared.open(state: state) }
            Button("Undo ClaudeBar's changes…") { UndoWindow.shared.open(state: state) }
        }
        .buttonStyle(.link).font(.caption)
        if SetupActions.statusLine(env: .real).canRestore {
            Button("Restore my old status line") {
                do {
                    restoreMessage = try SetupActions.statusLine(env: .real).restore().message
                    // Usage is off now: a full setup is reduced (the Settings line and Office card tell the truth).
                    state.setSetup(state.settings.setup.afterStatusLineRestore())
                } catch {
                    restoreMessage = (error as? StatusLineError)?.message ?? error.localizedDescription
                }
            }
            .buttonStyle(.link).font(.caption)
        }
        if let restoreMessage {
            Text(restoreMessage).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func heading(_ title: String) -> some View {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    }

    /// A folded section's header: a chevron, the title and an optional note ("3 of 4 on").
    private func fold(_ title: String, note: String? = nil, open: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { open.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: open.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).frame(width: 10)
                Text(title)
                if let note { Text("· \(note)").font(.caption).foregroundStyle(.secondary) }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func setting(_ title: String, _ value: Bool, _ change: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { value }, set: change)) {
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}

/// "ClaudeBar" with a cat on the left; ClaudeBar's ☀️/🌙 theme switch on the right.
struct TitleRow: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            // The menu bar's cat in its current pose; a plain cat while Cat Office is offline or empty.
            if let cat = state.menuCat {
                SpriteImage(key: "title-\(cat.cat)-\(cat.pose.rawValue)", fallback: nil) {
                    guard let data = await state.art.catImage(cat: cat.cat, pose: cat.pose) else { return nil }
                    return ArtCache.trimmed(data)
                }
                .frame(width: 20, height: 18)
            } else {
                Image(systemName: "cat.fill").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Text("ClaudeBar").font(.headline)
            Spacer()
            Button { state.helpShown.toggle() } label: {
                Text("?").font(.system(size: 12, weight: .bold))
                    .frame(width: 26, height: 18)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Help: what ClaudeBar shows, tips, and fixes")
            .accessibilityLabel("Help")
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { HelpButton.frame = $0 }
            .popover(isPresented: Binding(get: { state.helpShown }, set: { state.helpShown = $0 }), arrowEdge: .bottom) {
                HelpPanel().environmentObject(state)
            }
            Button { state.toggleOfficeLighting() } label: {
                Text(colorScheme == .dark ? "🌙" : "☀️").font(.system(size: 12))
                    .frame(width: 26, height: 18)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(colorScheme == .dark ? "Switch ClaudeBar to day" : "Switch ClaudeBar to night")
        }
    }
}

struct UsageHeader: View {
    let usage: UsageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Usage").font(.subheadline.weight(.semibold))
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
                    if row.helpers > 0 {
                        Text("+\(row.helpers) helper\(row.helpers == 1 ? "" : "s")")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                            .help("Sub-agents working in this project")
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

/// Holds a view and only takes clicks inside its own frame (plain NSView hit testing), clipping what spills out.
final class BoundedContainer: NSView {
    init(_ child: NSView) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        child.translatesAutoresizingMaskIntoConstraints = false
        addSubview(child)
        clipsToBounds = true
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: leadingAnchor),
            child.trailingAnchor.constraint(equalTo: trailingAnchor),
            child.topAnchor.constraint(equalTo: topAnchor),
            child.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? super.hitTest(point) : nil
    }
}
