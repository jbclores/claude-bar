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

    /// The tabs shown: no Office tab for "I don't use Cat Office" (SetupSettings.showsOffice).
    static func shown(officeShown: Bool) -> [DropdownTab] { officeShown ? allCases : [.projects, .settings] }

    /// The tab to show for `tab`: Projects in place of a hidden Office tab.
    static func showing(_ tab: DropdownTab, officeShown: Bool) -> DropdownTab {
        tab == .office && !officeShown ? .projects : tab
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
            UsageHeader(usage: state.output.usage, history: state.usageHistory, forecast: state.usageForecast,
                        quietEnds: state.quietEnds, showWeek: $state.usageWeekShown)
            if let error = state.configError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(Theme.waitingText)
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
            switch DropdownTab.showing(selection.tab, officeShown: state.officeShown) {
            case .office: OfficeTabView()
            case .projects: ProjectsTabView()
            case .settings: SettingsTabView()
            }
            Divider()
            HStack(spacing: 14) {
                if state.office != nil, state.officeShown {
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
            Picker("", selection: .constant(DropdownTab.showing(selection.tab, officeShown: state.officeShown))) {
                ForEach(DropdownTab.shown(officeShown: state.officeShown), id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
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
    var showsOffice: Bool { DropdownTab.showing(selection.tab, officeShown: state.officeShown) == .office }
    /// The tabs in the tab control, in order.
    private var shownTabs: [DropdownTab] = []
    private var attention = false
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
        tabs = FirstClickSegmentedControl(labels: [], trackingMode: .selectOne, target: self, action: #selector(tabChanged(_:)))
        tabs.controlSize = .large
        tabs.segmentDistribution = .fillEqually
        updateTabs()

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
        self.attention = attention
        if let i = shownTabs.firstIndex(of: .office) { tabs?.setLabel(attention ? "Office •" : "Office", forSegment: i) }
    }

    /// The tab control's segments: without the Office tab for "I don't use Cat Office" (it comes back once Cat Office
    /// is set up or running), the hidden tab's place taken by Projects.
    func updateTabs() {
        guard let tabs else { return }
        let wanted = DropdownTab.shown(officeShown: state.officeShown)
        if wanted != shownTabs {
            shownTabs = wanted
            tabs.segmentCount = wanted.count
            for (i, tab) in wanted.enumerated() {
                tabs.setLabel(tab.title, forSegment: i)
                tabs.setImage(NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title), forSegment: i)
                tabs.setImageScaling(.scaleProportionallyDown, forSegment: i)
            }
            updateAttention(attention)
            DispatchQueue.main.async { [weak self] in self?.resize() }
        }
        tabs.selectedSegment = wanted.firstIndex(of: DropdownTab.showing(selection.tab, officeShown: state.officeShown)) ?? 0
    }

    @objc private func tabChanged(_ sender: NSSegmentedControl) {
        guard shownTabs.indices.contains(sender.selectedSegment) else { return }
        selection.tab = shownTabs[sender.selectedSegment]
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
            if state.officeCopies.count > 1 { TwoCopiesCard() }
            FloorPicker()
            OfficeRoomView()
            if let rows = state.output.office {
                OfficeCatList(rows: rows)
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

/// Two copies of Cat Office run from one folder: each runs its own office, so ClaudeBar and the browser may disagree.
/// "Stop the extra one" stops the copies ClaudeBar doesn't read, after a warning.
struct TwoCopiesCard: View {
    @EnvironmentObject var state: AppState
    @State private var confirming = false

    var body: some View {
        let kept = state.officePortKept.map { "localhost:\($0)" } ?? "the first one"
        let extra = state.extraOfficeCopies.map { "\($0.port)" }.joined(separator: ", ")
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.waitingText)
            VStack(alignment: .leading, spacing: 3) {
                Text("Two copies of Cat Office are running, so the cats may not match").font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Stop the extra one") { confirming = true }.buttonStyle(.link).font(.caption)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.waiting.opacity(0.1)))
        .alert("Stop the copy on port \(extra)?", isPresented: $confirming) {
            Button("Stop it", role: .destructive) { state.stopExtraCopies() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Claude sessions running inside that copy will end. ClaudeBar keeps the one at \(kept): open that address in your browser.")
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

/// For "I don't use Cat Office": a friendly invitation to try it, at the top of Projects, until "Not now".
struct CatOfficeInvite: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "pawprint.fill").font(.title3).foregroundStyle(Theme.working)
            VStack(alignment: .leading, spacing: 4) {
                Text("Your sessions could be cats in a little office").font(.callout.weight(.semibold))
                Text("Cat Office shows each Claude session as a cat at its desk: napping when it's idle, snacking now and then, and waving when it needs you. It's a cosy way to keep an eye on your work.")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    Button("See how") { state.openHelpGuide(section: "cat-office") }
                    Button("Set up…") { SetupWindow.shared.open(state: state) }
                    Button("Not now") { state.catOfficeInviteDismissed = true }
                }
                .buttonStyle(.link).font(.caption)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.working.opacity(0.08)))
    }
}

struct ProjectsTabView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TodayRecapLine()
            if state.invitesToCatOffice { CatOfficeInvite() }
            if state.output.projects.isEmpty {
                Text("No projects yet").font(.callout).foregroundStyle(Theme.secondaryText)
            }
            ForEach(state.output.projects) { row in
                ProjectRowView(row: row,
                               onOpen: { NSWorkspace.shared.open(URL(fileURLWithPath: row.path)) },
                               onRemove: { state.remove(row) })
            }
            Button { chooseFolders() } label: { Label("Add folder…", systemImage: "plus") }
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
    /// The two folded sections: the four separate sounds, and Advanced (Refresh office art, Edit config file, Open log).
    @State private var soundsOpen = SettingsTabView.startOpen
    @State private var advancedOpen = SettingsTabView.startOpen
    /// Renders only: draw both folded sections open (`CLAUDEBAR_RENDER_SETTINGS_OPEN=1`).
    static var startOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            heading("General")
            setting("Open at login", state.launchAtLogin) { state.setLaunchAtLogin($0) }
            setting("Notify when a cat finishes", state.settings.notifications) { state.setNotifications($0) }
            setting("Warn before I hit a usage limit", state.settings.usageWarnings) { state.setUsageWarnings($0) }
            HStack {
                Text("Open ClaudeBar with")
                Spacer()
                if state.shortcutTaken { Text("That shortcut is taken; try another").font(.caption).foregroundStyle(Theme.waitingText) }
                ShortcutField()
            }
            // Cat Office's switches: not for "I don't use Cat Office" (they come back with the Office tab).
            if state.officeShown {
                setting("Start Cat Office with ClaudeBar", state.settings.catOffice.autoStart) { state.setAutoStart($0) }
                setting("Show the office on hover", state.settings.hoverPeek) { state.setHoverPeek($0) }
                setting("Show spare cats", state.settings.showSpareCats) { state.setShowSpareCats($0) }
                    .help("Also draw the office's own cats (the ones with no Claude session)")
            }
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
                    Button("Edit config file") { state.editConfig() }
                    Button("Open log") { state.openLauncherLog() }
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
        QuietHoursSettings()
        setting("Cat sounds", s.on) { state.setSound("on", $0) }
        if s.on {
            HStack(spacing: 8) {
                Text("Volume")
                Image(systemName: "speaker.fill").font(.caption).foregroundStyle(Theme.secondaryText)
                Slider(value: Binding(get: { state.settings.sounds.volume }, set: { state.setSoundVolume($0) }),
                       in: 0...1) { editing in if !editing { state.previewSound() } }
                    .controlSize(.small)
                Image(systemName: "speaker.wave.3.fill").font(.caption).foregroundStyle(Theme.secondaryText)
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
        let setup = state.setup
        let running = UserDefaults.standard.string(forKey: AppState.rememberedDirKey)
        heading("Setup")
        HStack(spacing: 4) {
            if setup.state == .full {
                Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Theme.working)
            }
            Text(setup.line(catOfficeDir: state.settings.catOffice.dir, runningDir: running, home: NSHomeDirectory()))
                .font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1).truncationMode(.middle)
        }
        .help(SetupSettings.folderPath(catOfficeDir: state.settings.catOffice.dir, runningDir: running,
                                       home: NSHomeDirectory()) ?? "")
        if state.officeShown {
            // How ClaudeBar reads Cat Office right now, ticking each second.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let c = ConnectionLine.text(url: state.office == nil ? nil : state.officeClient.baseURL, lastUpdate: state.lastOfficeUpdate,
                                            placesLive: MirrorPlaces.isLive(placesAt: state.office?.placesAt, now: context.date),
                                            copies: state.officeCopies.count, now: context.date)
                Text(c.line).font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(c.detail ?? "")
            }
        }
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
            Text(restoreMessage).font(.caption).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func heading(_ title: String) -> some View {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText)
    }

    /// A folded section's header: a chevron, the title and an optional note ("3 of 4 on").
    private func fold(_ title: String, note: String? = nil, open: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { open.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: open.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.secondaryText).frame(width: 10)
                Text(title)
                if let note { Text("· \(note)").font(.caption).foregroundStyle(Theme.secondaryText) }
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
                Image(systemName: "cat.fill").font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
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
    let history: UsageHistory
    let forecast: UsageForecast?
    /// When the quiet on now ends (nil: not quiet), for the 🔕.
    var quietEnds: Date? = nil
    /// The week chart (AppState.usageWeekShown: folded each time the dropdown opens).
    @Binding var showWeek: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Usage").font(.subheadline.weight(.semibold))
                if let quietEnds {
                    Image(systemName: "bell.slash.fill").font(.caption).foregroundStyle(Theme.secondaryText)
                        .help("Quiet until \(AppState.usageTime(quietEnds))")
                }
                Spacer()
                if let asOf = usage.asOf {
                    Text("as of \(Format.age(asOf, now: Date()))").font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
            row("5h", usage.fiveHourPct, usage.fiveHourResetsAt,
                extra: usage.workingCount > 0 ? "\(usage.workingCount) working" : nil)
            row("7d", usage.sevenDayPct, usage.sevenDayResetsAt, extra: nil)
            let today = history.today(now: Date(), calendar: .current)
            if today.count >= 2 { UsageSparkline(samples: today) }
            if let forecast { UsageForecastLine(forecast: forecast) }
            if showWeek { UsageWeekChart(history: history) }
        }
        // Click the usage area for the last 7 days; click again to fold them.
        .contentShape(Rectangle())
        .onTapGesture { showWeek.toggle() }
        .help(showWeek ? "Hide this week's usage" : "Show this week's usage")
    }

    private func row(_ label: String, _ pct: Double?, _ resets: Date?, extra: String?) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.caption.monospaced()).frame(width: 20, alignment: .leading)
            UsageBar(percent: pct)
            Text(pct.map(Format.percent) ?? "—").font(.caption.monospacedDigit()).frame(width: 36, alignment: .trailing)
            if let extra { Text(extra).font(.caption).foregroundStyle(Theme.working) }
            Spacer()
            if let resets { Text(Format.resets(resets, now: Date())).font(.caption).foregroundStyle(Theme.secondaryText) }
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
                        Text(row.needsAttention || status == .waiting ? "needs you" : status.rawValue)
                            .font(.caption).foregroundStyle(row.needsAttention ? Theme.waitingText : Theme.color(status))
                    }
                    if row.helpers > 0 {
                        Text("+\(row.helpers) helper\(row.helpers == 1 ? "" : "s")")
                            .font(.caption2.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                            .help("Sub-agents working in this project")
                    }
                    Spacer()
                    trailing.font(.caption).foregroundStyle(Theme.secondaryText)
                    if hovering {
                        Button(action: onRemove) { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(Theme.secondaryText).help("Remove from list")
                    }
                }
                detail.font(.caption).foregroundStyle(Theme.secondaryText)
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
            Text(row.branch.map { "\($0), no sessions yet" } ?? "No sessions yet")
        default:
            HStack(spacing: 6) {
                Text([row.branch, row.model].compactMap { $0 }.joined(separator: " · ")).lineLimit(1)
                if let ctx = row.contextPct {
                    // How full the session's context is.
                    Text("context").padding(.leading, 4)
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
