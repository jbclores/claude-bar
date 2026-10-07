import AppKit
import ClaudeBarCore
import ServiceManagement

enum OfficeLaunch: Equatable {
    case none
    case starting(since: Date)
    case failed(String)
}

/// Everything the menu bar shows: files and git re-read every 5 seconds, Cat Office's feed as it arrives.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var output = StatusOutput.empty
    @Published private(set) var office: OfficeSnapshot?
    @Published private(set) var needsAttention = false
    @Published private(set) var statusSince: [String: Date] = [:]
    /// Session keys that need the user (waiting, or just finished).
    @Published private(set) var attention: Set<String> = []
    @Published private(set) var configError: String?
    /// The current config, for the Settings tab.
    @Published private(set) var settings = Config.empty
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var officeLaunch = OfficeLaunch.none
    @Published private(set) var catIds: [String] = []
    /// The cat for the menu bar icon (nil: show the plain cat symbol).
    @Published private(set) var menuCat: MenuBarCat?

    let config = ConfigStore()
    private let snapshots = SnapshotReader()
    private let sessions = LiveSessionReader()
    private let git = GitBranchReader()
    private let officeSettings = LockedBox(CatOfficeSettings())
    private(set) lazy var officeClient = CatOfficeClient(
        settings: officeSettings,
        onBridge: { info in
            guard let dir = info.dir else { return }
            Task { @MainActor in UserDefaults.standard.set(dir, forKey: AppState.rememberedDirKey) }
        },
        onUpdate: { [weak self] snapshot in
            Task { @MainActor in self?.officeUpdated(snapshot) }
        })
    /// The folder Cat Office was last seen running from (so a moved folder is found without editing the config).
    static let rememberedDirKey = "catOfficeDir"
    private let notifier = Notifier()
    private let launcher = CatOfficeLauncher()
    private(set) lazy var art: ArtCache = { [officeClient] in ArtCache(baseURL: { officeClient.baseURL }) }()
    private var tracker = AttentionTracker()
    private var files: StatusInput?
    private var timer: Timer?
    private var refreshing = false
    /// Off for `--render-peek`: no auto-start, no notifications.
    var sideEffects = true

    func start() {
        loadCatalog()
        refresh()
        officeClient.start()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // Give the feed a moment to connect; start Cat Office only if it's still unreachable.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if sideEffects, office == nil, config.config.catOffice.autoStart { startCatOffice() }
        }
    }

    /// Starts Cat Office's dev server unless something already answers at its address.
    func startCatOffice() {
        if case .starting = officeLaunch { return }
        let started = Date()
        officeLaunch = .starting(since: started)
        var settings = config.config.catOffice
        settings.dir = CatOfficeDiscovery.folderToStart(
            configured: settings.dir, remembered: UserDefaults.standard.string(forKey: Self.rememberedDirKey))
        Task { @MainActor in
            switch await launcher.start(settings: settings) {
            case .started, .alreadyRunning:
                // Reconnect right away a few times while the server comes up.
                for delay in [2, 3, 5, 8, 12] as [UInt64] {
                    try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                    if office != nil { break }
                    officeClient.reconnectNow()
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if office == nil, officeLaunch == .starting(since: started) { officeLaunch = .failed("Couldn't start Cat Office") }
            case .notConfigured:
                officeLaunch = .failed("Cat Office's folder isn't known: set catOffice.dir in the config")
            case .npmNotFound:
                officeLaunch = .failed("npm not found")
            case .failed(let message):
                officeLaunch = .failed("Couldn't start Cat Office: \(message)")
            }
        }
    }

    func openLauncherLog() {
        NSWorkspace.shared.open(CatOfficeLauncher.logFile)
    }

    /// Re-reads the config, snapshots, sessions and branches (off the main thread), then rebuilds the rows.
    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        config.reload()
        configError = config.error
        if settings != config.config { settings = config.config }
        officeSettings.set(config.config.catOffice)
        let projects = config.config.projects
        let snapshots = snapshots, sessions = sessions, git = git
        Task.detached(priority: .utility) {
            let input = Self.readFiles(projects: projects, snapshots: snapshots, sessions: sessions, git: git)
            await self.filesRead(input)
        }
    }

    nonisolated private static func readFiles(projects: [Project], snapshots: SnapshotReader,
                                              sessions: LiveSessionReader, git: GitBranchReader) -> StatusInput {
        var branches: [String: String] = [:]
        var existing = Set<String>()
        for p in projects {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: p.path, isDirectory: &isDir), isDir.boolValue else { continue }
            existing.insert(p.path)
            if let b = git.branch(at: p.path) { branches[p.path] = b }
        }
        return StatusInput(projects: projects, snapshots: snapshots.read(), fallbackSessions: sessions.read(),
                           branches: branches, existing: existing, planUsage: PlanUsageReader().read())
    }

    private func filesRead(_ input: StatusInput) {
        files = input
        refreshing = false
        recompute()
    }

    private func officeUpdated(_ snapshot: OfficeSnapshot?) {
        var snapshot = snapshot
        // Renders only (CLAUDEBAR_RENDER_DESK="design,flip,rear"): try a desk on the working cats.
        if !sideEffects, let spec = ProcessInfo.processInfo.environment["CLAUDEBAR_RENDER_DESK"], snapshot != nil {
            let p = spec.split(separator: ",").map(String.init)
            if p.count == 3 {
                for i in snapshot!.agents.indices where snapshot!.agents[i].status == .working {
                    snapshot!.agents[i].desk = AgentDesk(id: p[0], flip: p[1] == "1", rear: p[2] == "1")
                }
            }
        }
        guard snapshot != office else { return }
        let cameOnline = office == nil && snapshot != nil
        office = snapshot
        if snapshot != nil { officeLaunch = .none }
        if cameOnline { loadCatalog() }
        recompute()
    }

    private func recompute() {
        guard var input = files else { return }
        input.office = office
        let tracked = StatusModel.trackedSessions(fallback: input.fallbackSessions, office: office)
        let finished = tracker.update(tracked, now: Date())
        if sideEffects, config.config.notifications { finished.forEach(notifier.post) }
        input.attention = tracker.attention
        input.statusSince = tracker.since
        statusSince = tracker.since
        if attention != tracker.attention { attention = tracker.attention }
        needsAttention = !tracker.attention.isEmpty
        output = StatusModel.build(input)
        let cat = office.flatMap {
            MenuBarCat.pick(agents: $0.agents, attention: tracker.attention, catIds: catIds,
                            since: tracker.since, current: menuCat?.agentId)
        }
        if cat != menuCat { menuCat = cat }
    }

    /// Cat ids for picking each agent's cat (from Cat Office, or the copy cached last time).
    private func loadCatalog() {
        Task { @MainActor in
            if let catalog = await art.catalog(), catalog.catIds != catIds {
                catIds = catalog.catIds
                recompute()
            }
        }
    }

    /// The user opened the dropdown or the peek.
    func acknowledge() {
        tracker.acknowledge()
        recompute()
    }

    func addFolders(_ urls: [URL]) {
        do { try config.add(paths: urls.map(\.path)) } catch let e as ConfigError { configError = e.message } catch {}
        refresh()
    }

    func remove(_ row: ProjectRow) {
        do { try config.remove(path: row.path) } catch let e as ConfigError { configError = e.message } catch {}
        refresh()
    }

    func setNotifications(_ on: Bool) { setSetting(on, at: ["notifications"]) }
    func setAutoStart(_ on: Bool) { setSetting(on, at: ["catOffice", "autoStart"]) }
    func setHoverPeek(_ on: Bool) { setSetting(on, at: ["hoverPeek"]) }

    func setOfficeLighting(_ lighting: OfficeLighting) {
        do { try config.set(lighting.rawValue, at: ["officeLighting"]) } catch let e as ConfigError { configError = e.message } catch {}
        settings = config.config
    }

    /// The office's ☀️/🌙 pill: the opposite of what's showing now.
    func toggleOfficeLighting() {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        setOfficeLighting(settings.officeLighting.toggled(systemDark: dark))
    }

    private func setSetting(_ value: Bool, at path: [String]) {
        do { try config.set(value, at: path) } catch let e as ConfigError { configError = e.message } catch {}
        settings = config.config
    }

    func editConfig() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-t", config.file.path]
        try? p.run()
    }

    func openCatOffice() {
        NSWorkspace.shared.open(officeClient.baseURL)
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("ClaudeBar: launch at login failed: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
