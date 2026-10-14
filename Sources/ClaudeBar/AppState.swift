import AppKit
import ClaudeBarCore
import ServiceManagement

/// An answer sent from ClaudeBar for a waiting session: on its way, taken by Cat Office (when), or why not (plain words).
enum AnswerState: Equatable {
    case sending, sent(at: Date), failed(String)
}

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
    /// cats.json's sprite canvas, and each cat's walking frame count (cats.ts catWalkFrames).
    @Published private(set) var catFrame: CatFrame = .standard
    @Published private(set) var walkFrameCounts: [String: Int] = [:]
    /// Cat Office's floors (the fallback Lounge until it has loaded).
    @Published private(set) var building = Building.fallback { didSet { rebuildRooms() } }
    /// Cat Office's room parts, props and desks (nil until loaded).
    @Published private(set) var catalogue: RoomCatalogue? { didSet { rebuildRooms() } }
    /// Each floor's built room, by floor id (floors without a room, corners or catalogue are absent).
    @Published private(set) var rooms: [Int: BuiltRoom] = [:]
    /// Each floor's walking grid, built with its room (floors without a valid grid are absent).
    @Published private(set) var navs: [Int: NavGrid] = [:]

    private func rebuildRooms() {
        defer { updateMirror() }
        guard let c = catalogue else { rooms = [:]; navs = [:]; return }
        rooms = Dictionary(building.floors.compactMap { f in RoomGeometry.build(floor: f, catalogue: c).map { (f.id, $0) } },
                           uniquingKeysWith: { first, _ in first })
        navs = Dictionary(uniqueKeysWithValues: rooms.compactMap { id, room in
            building.floors.first { $0.id == id }.flatMap { NavGrid(floor: $0, room: room) }.map { (id, $0) }
        })
    }

    private func loadCatalogue() {
        Task { @MainActor in
            if let c = await art.roomCatalogue(), c != catalogue { catalogue = c }
        }
    }

    /// Where Follow points now (FloorPlan.followTarget).
    var followFloor: Int {
        FloorPlan.followTarget(building: building, agents: office?.agents ?? [], attention: attention, since: statusSince, now: Date(),
                               mirror: mirror)
    }

    /// The browser's office while a Cat Office page shares its cats' places (OfficeMirror), else `.off`: the office
    /// views place cats with it. Re-checked on every feed update and when the places go stale.
    @Published private(set) var mirror = OfficeMirror.off
    private var mirrorExpiry: DispatchWorkItem?

    private func updateMirror() {
        let now = Date()
        // Renders only: CLAUDEBAR_RENDER_SPARES=1 shows spare cats without touching the config.
        let spares = mirrorShowsSpares
        simHost.update(agents: office?.agents ?? [], building: building, rooms: rooms, grids: navs, spares: catalogCats, showSpares: spares)
        renderAdvance(now: now)
        let live = MirrorPlaces.isLive(placesAt: office?.placesAt, now: now)
        publish(simHost.mirror(OfficeMirror(office, now: now, showSpares: spares), live: live, now: now))
        mirrorExpiry?.cancel()
        mirrorExpiry = nil
        // No new post within MirrorPlaces.liveFor: the rules take over then.
        guard let at = office?.placesAt, MirrorPlaces.isLive(placesAt: at, now: now) else { return }
        let item = DispatchWorkItem { [weak self] in self?.updateMirror() }
        mirrorExpiry = item
        let left = at / 1000 + MirrorPlaces.liveFor - now.timeIntervalSince1970
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, left) + 0.05, execute: item)
    }

    // MARK: the office's own life (OfficeSim, spec section 3)

    /// Cat Office's office life for the idle cats (and spares with the switch on) while no page shares its places.
    private lazy var simHost = SimHost(seed: Self.simSeed(sideEffects: sideEffects), now: launched)
    /// Steps the sim while the office is on screen; nil while it's closed (nothing runs then).
    private(set) var simTimer: Timer?
    /// Bumped when the office's cats were placed at once (the catch-up on opening): the views place them, no walks.
    @Published private(set) var simPlacement = 0
    /// cats.json's cats, for the spare roster.
    private var catalogCats: [SpareRoster.Cat] = []
    static let simTick: TimeInterval = 0.25
    private var renderAdvanced = false

    /// A new seed each launch; renders use a fixed one.
    private static func simSeed(sideEffects: Bool) -> UInt32 {
        // Renders: CLAUDEBAR_SIM_SEED, else 42, so a render is the same each time.
        if !sideEffects { return ProcessInfo.processInfo.environment["CLAUDEBAR_SIM_SEED"].flatMap(UInt32.init) ?? 42 }
        return UInt32.random(in: .min ... .max)
    }

    /// The office (Office tab or hover peek) is on screen.
    private var officeOnScreen: Bool { officeTabShown || peekShownSince != nil }

    /// The office opened or closed: opening catches up and places the cats; the step timer runs only while open.
    private func updateSimClock() {
        let on = officeOnScreen
        guard on != simHost.visible else { return }
        let placed = simHost.placement
        simHost.setVisible(on, now: Date())
        if on {
            if simTimer == nil {
                let timer = Timer(timeInterval: Self.simTick, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.simTicked() }
                }
                // Also while a menu or scroll tracks the mouse.
                RunLoop.main.add(timer, forMode: .common)
                simTimer = timer
            }
        } else {
            simTimer?.invalidate()
            simTimer = nil
        }
        if simHost.placement != placed { simPlacement = simHost.placement }
        logSim(on ? "office open" : "office closed")
        updateMirror()
    }

    private func simTicked() {
        let now = Date()
        simHost.tick(now: now)
        // A long stall (the Mac slept with the office open) was a catch-up: placed, not walked.
        if simHost.placement != simPlacement { simPlacement = simHost.placement }
        let live = MirrorPlaces.isLive(placesAt: office?.placesAt, now: now)
        guard !live else { return }
        publish(simHost.mirror(.off, live: false, now: now))
    }

    /// Who sits where on each floor (SimHost.seatings): the one seating both office views draw rule-placed cats with,
    /// so the desks the sim keeps its cats off are the ones drawn.
    @Published private(set) var seatings: [Int: FloorSeating] = [:]

    /// Each cat's minutes left at its spot (SimHost.minutesLeft), apart from `mirror` so a countdown redraws only the
    /// hover card that shows it, not every view watching the app state.
    let minutesLeft = MinutesLeft()

    private func publish(_ next: OfficeMirror) {
        if simHost.seatings != seatings { seatings = simHost.seatings }
        if next != mirror { mirror = next }
        if simHost.minutesLeft != minutesLeft.byCat { minutesLeft.byCat = simHost.minutesLeft }
    }

    /// Renders only (CLAUDEBAR_SIM_ADVANCE=<minutes>): once the cats are in, that many sim minutes at once.
    private func renderAdvance(now: Date) {
        guard !sideEffects, !renderAdvanced, !rooms.isEmpty, !simHost.cats.isEmpty,
              let minutes = ProcessInfo.processInfo.environment["CLAUDEBAR_SIM_ADVANCE"].flatMap(Double.init) else { return }
        // The spares join once cats.json is in (when they're shown).
        if simHost.cats.allSatisfy({ !$0.isSpare }), mirrorShowsSpares, catalogCats.isEmpty { return }
        renderAdvanced = true
        simHost.advance(minutes: minutes, now: now)
        simPlacement = simHost.placement
        logSim("advanced \(minutes) min")
    }

    private var mirrorShowsSpares: Bool {
        settings.showSpareCats || (!sideEffects && ProcessInfo.processInfo.environment["CLAUDEBAR_RENDER_SPARES"] == "1")
    }

    /// Renders only: the sim's clock, so a render shows that nothing runs while the office is closed.
    private func logSim(_ what: String) {
        guard !sideEffects else { return }
        print("sim: \(what): step timer \(simTimer == nil ? "nil" : "running"), sim time \(String(format: "%.2f", simHost.sim.time)) min,",
              "\(simHost.cats.filter { !$0.isSpare }.count) session cats, \(simHost.cats.filter(\.isSpare).count) spares, taken desks \(simHost.takenSpotIds.count)")
    }

    private func loadBuilding() {
        Task { @MainActor in
            if let b = await art.building(), b != building { building = b }
        }
    }
    /// The cat for the menu bar icon (nil: show the plain cat symbol).
    @Published private(set) var menuCat: MenuBarCat?

    let config: ConfigStore

    /// `config` defaults to the real projects.json; the setup click test passes a temp one.
    init(config: ConfigStore = ConfigStore()) {
        self.config = config
    }
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
    nonisolated static let rememberedDirKey = "catOfficeDir"
    private let notifier = Notifier()
    private let soundPlayer = CatSoundPlayer()
    private var soundGate = SoundGate()
    /// The ❓ help panel is open.
    @Published var helpShown = false

    /// The full guide that ships inside the app (Resources/Help/guide.html).
    var helpGuide: URL? { Bundle.main.url(forResource: "guide", withExtension: "html", subdirectory: "Help") }

    /// "What ClaudeBar changes" (its own page: macOS drops #anchors when opening a local file).
    var changesPage: URL? { Bundle.main.url(forResource: "changes", withExtension: "html", subdirectory: "Help") }

    func openChangesPage() {
        guard let url = changesPage else { return }
        NSWorkspace.shared.open(url)
    }

    /// When the last snapshot from Cat Office arrived (the feed sends one at least every 5 s), for Settings' connection line.
    @Published private(set) var lastOfficeUpdate: Date?
    /// Cat Office's dev servers running from its folder (CatOfficeServers): more than one means two offices that disagree.
    @Published private(set) var officeCopies: [CatOfficeServers.Server] = []
    /// Cat Office answers at its address though the feed isn't connected yet: "Connecting…", not "isn't running".
    @Published private(set) var officeAnswers = false
    private var copiesCheckedAt = Date.distantPast
    private var checkingCopies = false

    /// Looks for running copies of Cat Office (every 15 s at most), and whether one answers while the feed is down (then
    /// reconnects at once instead of waiting out the backoff).
    func checkCopies(force: Bool = false) {
        guard !checkingCopies, force || Date().timeIntervalSince(copiesCheckedAt) >= 15 else { return }
        if !sideEffects { renderCopies(); return }
        checkingCopies = true
        copiesCheckedAt = Date()
        let folder = CatOfficeDiscovery.folderToStart(configured: settings.catOffice.dir,
                                                      remembered: UserDefaults.standard.string(forKey: Self.rememberedDirKey))
        let offline = office == nil, url = officeClient.baseURL
        Task.detached(priority: .utility) {
            let copies = folder.map { CatOfficeServers.find(folder: $0) } ?? []
            let answers = offline ? await CatOfficeLauncher.answers(url) : false
            await MainActor.run {
                self.checkingCopies = false
                if copies != self.officeCopies { self.officeCopies = copies }
                let was = self.officeAnswers
                self.officeAnswers = answers && self.office == nil
                if self.officeAnswers, !was { self.officeClient.reconnectNow() }
            }
        }
    }

    /// Renders only: CLAUDEBAR_RENDER_TWO_COPIES=1 (two copies running), CLAUDEBAR_RENDER_CONNECTING=1 (one answers).
    private func renderCopies() {
        let env = ProcessInfo.processInfo.environment
        if env["CLAUDEBAR_RENDER_TWO_COPIES"] == "1" {
            officeCopies = [CatOfficeServers.Server(pid: 1, port: 5173), CatOfficeServers.Server(pid: 2, port: 5174)]
        }
        officeAnswers = env["CLAUDEBAR_RENDER_CONNECTING"] == "1" && office == nil
    }

    /// The copy ClaudeBar keeps (the one it reads), and the ones "Stop the extra one" stops.
    var officePortKept: Int? { officeClient.baseURL.port }
    var extraOfficeCopies: [CatOfficeServers.Server] { CatOfficeServers.extra(officeCopies, connectedPort: officePortKept) }

    /// Stops the copies of Cat Office ClaudeBar doesn't read, then looks again.
    func stopExtraCopies() {
        guard sideEffects else { return }
        for copy in extraOfficeCopies { CatOfficeServers.stop(copy) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.checkCopies(force: true) }
    }

    /// The guide, at `section` (an id in guide.html) when given.
    func openHelpGuide(section: String? = nil) {
        guard let url = helpGuide else { return }
        guard let section, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            NSWorkspace.shared.open(url)
            return
        }
        parts.fragment = section
        NSWorkspace.shared.open(parts.url ?? url)
    }

    /// The Office tab and the hover peek show: not for "I don't use Cat Office", unless one is running anyway.
    var officeShown: Bool { setup.showsOffice(officeLive: officeLive) }

    /// Renders only (CLAUDEBAR_RENDER_NO_CAT_OFFICE=1): as someone who chose "I don't use Cat Office", none running.
    private var renderNoCatOffice: Bool { !sideEffects && ProcessInfo.processInfo.environment["CLAUDEBAR_RENDER_NO_CAT_OFFICE"] == "1" }
    /// How far setup got (in renders with CLAUDEBAR_RENDER_NO_CAT_OFFICE: "I don't use Cat Office").
    var setup: SetupSettings { renderNoCatOffice ? SetupSettings(seen: true, state: .noCatOffice) : settings.setup }
    private var officeLive: Bool { office != nil && !renderNoCatOffice }

    /// "Not now" on the Projects tab's invitation to Cat Office (a preference: it stays hidden).
    static let inviteDismissedKey = "catOfficeInviteDismissed"
    @Published var catOfficeInviteDismissed = UserDefaults.standard.bool(forKey: AppState.inviteDismissedKey) {
        didSet { UserDefaults.standard.set(catOfficeInviteDismissed, forKey: Self.inviteDismissedKey) }
    }

    /// The Projects tab shows its invitation to try Cat Office.
    var invitesToCatOffice: Bool {
        setup.invitesToCatOffice(dismissed: catOfficeInviteDismissed && !renderNoCatOffice, officeLive: officeLive)
    }

    /// The office is on screen (the hover peek, or the dropdown): the click meow and elevator ding only play then.
    var officeVisible = false
    private lazy var lofi = LofiPlayer()
    /// The dropdown is open on its Office tab.
    var officeTabShown = false { didSet { if officeTabShown != oldValue { updateMusic(); updateSimClock() } } }
    /// When the hover popup opened (nil while closed): the music waits OfficeMusic.popupDelay before starting.
    var peekShownSince: Date? {
        didSet {
            guard peekShownSince != oldValue else { return }
            updateMusic()
            if (peekShownSince == nil) != (oldValue == nil) { updateSimClock() }
            if peekShownSince != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + OfficeMusic.popupDelay + 0.05) { [weak self] in self?.updateMusic() }
            }
        }
    }
    private let launcher = CatOfficeLauncher()
    private(set) lazy var art: ArtCache = { [officeClient] in ArtCache(baseURL: { officeClient.baseURL }) }()
    /// Cat Office's Bongo Cat cursor over the office room (dropdown and peek).
    private(set) lazy var roomCursor = RoomCursor(art: art)
    private var tracker = AttentionTracker()
    private var files: StatusInput?
    private var timer: Timer?
    private var buildingTimer: Timer?
    private let launched = Date()
    /// Renders only: re-applies the last feed snapshot (so CLAUDEBAR_RENDER_FLIP_AT takes effect without waiting for one).
    func replayOffice() { officeUpdated(office) }
    private var refreshing = false
    /// Off for `--render-peek`: no auto-start, no notifications.
    var sideEffects = true

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.macWillSleep() }
        }
        loadCatalog()
        refresh()
        officeClient.start()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // Cat Office adds a floor when a new project shows up.
        buildingTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.loadBuilding(); self?.loadCatalogue(); self?.checkArt() }
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
        // Renders and click tests never start Cat Office.
        guard sideEffects else { return }
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
        if settings != config.config {
            settings = config.config
            applyLighting()
            updateMirror()
        }
        officeSettings.set(config.config.catOffice)
        checkCopies()
        if let until = quietUntil, until <= Date() { setQuietUntil(nil) }
        updateMusic()
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
        // Renders only (CLAUDEBAR_RENDER_FLIP_AT=seconds): working cats go idle after that long, to watch them walk.
        if !sideEffects, let after = ProcessInfo.processInfo.environment["CLAUDEBAR_RENDER_FLIP_AT"].flatMap(Double.init),
           Date().timeIntervalSince(launched) > after, snapshot != nil {
            if ProcessInfo.processInfo.environment["CLAUDEBAR_RENDER_FLIP_TO"] == "working" {
                // The first idle cat (by name) starts working: it walks from the lounge to a desk.
                if let i = snapshot!.agents.indices.filter({ snapshot!.agents[$0].status == .idle })
                    .min(by: { snapshot!.agents[$0].name < snapshot!.agents[$1].name }) { snapshot!.agents[i].status = .working }
            } else {
                for i in snapshot!.agents.indices where snapshot!.agents[i].status == .working { snapshot!.agents[i].status = .idle }
            }
        }
        // Renders only (CLAUDEBAR_RENDER_SUBAGENT=n): n stand-in helpers working for the first working office cat.
        if !sideEffects, let n = ProcessInfo.processInfo.environment["CLAUDEBAR_RENDER_SUBAGENT"].flatMap(Int.init), n > 0, snapshot != nil,
           let parent = snapshot!.agents.first(where: { $0.isOffice && $0.status == .working && $0.repoRoot != nil })
               ?? snapshot!.agents.first(where: { $0.isOffice && $0.status == .working }) {
            let jobs = [("Explore", "Review Cat Office walking"), ("general-purpose", "Write the walking tests"),
                        ("Explore", "Find desk geometry"), ("Plan", "Plan the sub-agent list"), ("Explore", "Check feed fields"),
                        ("general-purpose", "Render previews")]
            for i in 0..<n {
                let id = "helper\(i)a69adf54739f"
                var helper = OfficeAgent(id: id, name: id, status: .working, cwd: parent.cwd, repoName: parent.repoName,
                                         repoRoot: parent.repoRoot, model: "claude-haiku-4-5", lastAction: "Grep: walkFrame", sessionId: id)
                helper.kind = "subagent"; helper.parentName = parent.name
                (helper.agentType, helper.agentDescription) = jobs[i % jobs.count]
                snapshot!.agents.append(helper)
            }
            // CLAUDEBAR_RENDER_PARENT_IDLE=1: the parent has finished while its helpers work on (they stay with it, in the Lounge).
            if ProcessInfo.processInfo.environment["CLAUDEBAR_RENDER_PARENT_IDLE"] == "1",
               let i = snapshot!.agents.firstIndex(where: { $0.id == parent.id }) { snapshot!.agents[i].status = .idle }
        }
        // Renders only (CLAUDEBAR_RENDER_PLACES=<json file>): the browser's places for some cats, posted just now.
        // CLAUDEBAR_RENDER_PLACES="a.json,b.json" with CLAUDEBAR_RENDER_FLIP_TO=places: b.json after CLAUDEBAR_RENDER_FLIP_AT.
        if !sideEffects, let spec = ProcessInfo.processInfo.environment["CLAUDEBAR_RENDER_PLACES"], snapshot != nil {
            let files = spec.split(separator: ",").map(String.init)
            let after = ProcessInfo.processInfo.environment["CLAUDEBAR_RENDER_FLIP_AT"].flatMap(Double.init)
            // Each further file after the second comes `CLAUDEBAR_RENDER_PLACES_STEP` seconds (default 3) after the one before.
            let step = ProcessInfo.processInfo.environment["CLAUDEBAR_RENDER_PLACES_STEP"].flatMap(Double.init) ?? 3
            let elapsed = Date().timeIntervalSince(launched)
            let index = ProcessInfo.processInfo.environment["CLAUDEBAR_RENDER_FLIP_TO"] == "places"
                ? after.map { a in elapsed > a ? min(files.count - 1, 1 + Int((elapsed - a) / step)) : 0 } ?? 0 : 0
            if let file = files.indices.contains(index) ? files[index] : files.first { Self.renderPlaces(file: file, into: &snapshot!) }
        }
        // Renders and the answer click test (CLAUDEBAR_RENDER_WAITING=<permission|question|plan>): the first office
        // agent waits on a sample prompt.
        if !sideEffects, let kind = ProcessInfo.processInfo.environment["CLAUDEBAR_RENDER_WAITING"], snapshot != nil,
           let prompt = Self.samplePrompt(kind), let i = Self.renderWaitingIndex(&snapshot!.agents) {
            snapshot!.agents[i].status = .waiting
            snapshot!.agents[i].pendingPrompt = prompt
            renderWaitingId = snapshot!.agents[i].id
        }
        if snapshot != nil {
            lastOfficeUpdate = Date()
            if officeAnswers { officeAnswers = false }
        }
        guard snapshot != office else { updateMirror(); return }
        let cameOnline = office == nil && snapshot != nil
        // Only the browser's places moved (every 2 s while a Cat Office page is shown): the mirror, not the status.
        let placesOnly = office.flatMap { old in snapshot.map(old.sameExceptPlaces) } ?? false
        // "Sent" or an error no longer applies once the agent stops waiting or waits on something else.
        for id in AnswerReset.stale(Set(answerState.keys), before: office?.agents ?? [], after: snapshot?.agents ?? []) {
            answerState[id] = nil
        }
        office = snapshot
        renderAnswerState()
        updateMirror()
        if snapshot != nil { officeLaunch = .none }
        if cameOnline { loadCatalog() }
        if !placesOnly { recompute() }
    }

    /// Renders only: a JSON object of agent (its id, session id, name, project name or label; a main agent before its
    /// helpers) → place (the bridge's shape; `at` may be left out), put on those agents with a fresh `placesAt`.
    /// The key "_spares" holds a list of spare cats' places (with "name" and "key").
    private static func renderPlaces(file: String, into snapshot: inout OfficeSnapshot) {
        guard let data = FileManager.default.contents(atPath: file),
              var all = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            print("CLAUDEBAR_RENDER_PLACES: can't read \(file)")
            return
        }
        let now = Date().timeIntervalSince1970 * 1000
        let spares = (all.removeValue(forKey: "_spares") as? [[String: Any]]) ?? []
        snapshot.spares = spares.compactMap { raw in
            var raw = raw
            if raw["at"] == nil { raw["at"] = now }
            guard let json = try? JSONSerialization.data(withJSONObject: raw) else { return nil }
            return try? JSONDecoder().decode(MirrorPlace.self, from: json)
        }
        let places = all.compactMapValues { $0 as? [String: Any] }
        for (who, raw) in places {
            var raw = raw
            if raw["at"] == nil { raw["at"] = now }
            guard let json = try? JSONSerialization.data(withJSONObject: raw),
                  let place = try? JSONDecoder().decode(MirrorPlace.self, from: json),
                  let i = snapshot.agents.indices.filter({ [snapshot.agents[$0].id, snapshot.agents[$0].sessionId, snapshot.agents[$0].name,
                                                             snapshot.agents[$0].repoName, snapshot.agents[$0].label].contains(who) })
                      .min(by: { (snapshot.agents[$0].isSubagent ? 1 : 0, $0) < (snapshot.agents[$1].isSubagent ? 1 : 0, $1) }) else {
                print("CLAUDEBAR_RENDER_PLACES: no agent or bad place for \(who)")
                continue
            }
            snapshot.agents[i].place = place
        }
        snapshot.placesAt = now
    }

    private func recompute() {
        guard var input = files else { return }
        input.office = office
        let tracked = StatusModel.trackedSessions(fallback: input.fallbackSessions, office: office)
        let finished = tracker.update(tracked, now: Date())
        recordSessions(tracked, fallback: input.fallbackSessions)
        if sideEffects {
            let now = Date()
            // Quiet hours: no notifications or sounds (they aren't sent later).
            for event in finished where !isQuiet {
                let sound = soundGate.sound(for: .finished(event.key), settings: settings.sounds, now: now)
                if config.config.notifications {
                    let volume = settings.sounds.volume
                    notifier.post(event, sound: sound) { [weak self] s in
                        Task { @MainActor in self?.soundPlayer.play(s, volume: volume) }
                    }
                } else if let sound {
                    soundPlayer.play(sound, volume: settings.sounds.volume)
                }
            }
            for key in tracker.startedWaiting { playSound(.needsYou(key)) }
        }
        input.attention = tracker.attention
        input.statusSince = tracker.since
        statusSince = tracker.since
        if attention != tracker.attention { attention = tracker.attention }
        needsAttention = !tracker.attention.isEmpty
        output = StatusModel.build(input)
        recordUsage(output.usage)
        let cat = office.flatMap {
            MenuBarCat.pick(agents: $0.agents, attention: tracker.attention, catIds: catIds,
                            since: tracker.since, current: menuCat?.agentId)
        }
        if cat != menuCat { menuCat = cat }
    }

    /// Every minute: a changed cat list (a character added in Cat Office's cat builder), and, while the office is on
    /// screen, the pictures in use (an edited character or piece of furniture). Cheap "has it changed?" checks.
    private func checkArt() {
        guard sideEffects, office != nil else { return }
        Task { @MainActor in
            if let catalog = await art.catalog(refresh: true) { catalogLoaded(catalog) }
            if officeVisible, await art.revalidate() { ArtGeneration.shared.bump() }
        }
    }

    /// Settings → Advanced → Refresh office art: check everything with Cat Office now (floors, furniture, characters).
    func refreshArt() {
        Task { @MainActor in
            if let catalog = await art.catalog(refresh: true) { catalogLoaded(catalog) }
            await art.revalidate(force: true)
            loadBuilding()
            loadCatalogue()
            ArtGeneration.shared.bump()
        }
    }

    /// Cat ids for picking each agent's cat (from Cat Office, or the copy cached last time).
    private func loadCatalog() {
        Task { @MainActor in
            if let catalog = await art.catalog() { catalogLoaded(catalog) }
            loadBuilding()
            loadCatalogue()
        }
    }

    /// A changed cat list: the agents' cats, and the spare roster.
    private func catalogLoaded(_ catalog: CatCatalog) {
        if catalog.catIds != catIds {
            catIds = catalog.catIds
            recompute()
        }
        if catalog.frame != catFrame { catFrame = catalog.frame }
        simHost.sim.sleepPoses = catalog.simSleepPoses
        let counts = Dictionary(uniqueKeysWithValues: catalog.catIds.map { ($0, catalog.walkFrames(cat: $0).count) })
        if counts != walkFrameCounts { walkFrameCounts = counts }
        if catalog.cats != catalogCats {
            catalogCats = catalog.cats
            updateMirror()
        }
    }

    /// A spare cat's role in words ("UI/UX Designer"), as Cat Office's roster gives it.
    func spareRole(_ agent: OfficeAgent) -> String? {
        agent.isSpare ? SpareRoster.roleLabel(spareKey: agent.id, cats: catalogCats) : nil
    }

    /// The user opened the dropdown or the peek.
    func acknowledge() {
        usageWeekShown = false
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
    func setShowSpareCats(_ on: Bool) { setSetting(on, at: ["office", "spareCats"]) }

    func setUsageWarnings(_ on: Bool) { setSetting(on, at: ["usageWarnings"]) }

    // MARK: Quiet hours

    /// "Quiet for 1 hour": until when (a preference, so it lasts through a restart; ends by itself).
    static let quietUntilKey = "quietUntil"
    @Published private(set) var quietUntil: Date? = {
        // Renders only: CLAUDEBAR_RENDER_QUIET=1 is quiet for the next hour (in memory).
        if ProcessInfo.processInfo.environment["CLAUDEBAR_RENDER_QUIET"] == "1" { return Date().addingTimeInterval(3600) }
        let d = UserDefaults.standard.object(forKey: AppState.quietUntilKey) as? Date
        return d.flatMap { $0 > Date() ? $0 : nil }
    }()

    /// No ClaudeBar sounds or notifications now (quiet hours, or "Quiet for 1 hour").
    var isQuiet: Bool { settings.quietHours.isQuiet(at: Date(), calendar: .current, quietUntil: quietUntil) }
    /// When the quiet on now ends.
    var quietEnds: Date? { settings.quietHours.quietEnds(at: Date(), calendar: .current, quietUntil: quietUntil) }

    func quietForAnHour() { setQuietUntil(Date().addingTimeInterval(3600)) }
    func endQuietHour() { setQuietUntil(nil) }
    private func setQuietUntil(_ date: Date?) {
        quietUntil = date
        if sideEffects { UserDefaults.standard.set(date, forKey: Self.quietUntilKey) }
        updateMusic()
    }

    func setQuietHours(on: Bool) { setSetting(on, at: ["quietHours", "on"]); updateMusic() }
    func setQuietWeekends(_ on: Bool) { setSetting(on, at: ["quietHours", "weekends"]); updateMusic() }
    /// `from` or `to`, minutes after midnight.
    func setQuietTime(_ key: String, minutes: Int) {
        do { try config.set(QuietHours.clock(minutes), at: ["quietHours", key]) } catch let e as ConfigError { configError = e.message } catch {}
        settings = config.config
        updateMusic()
    }

    // MARK: Shortcut

    /// The shortcut couldn't be registered (another app has it): the Settings box says so.
    @Published var shortcutTaken = false
    /// Where the shortcut box is, for the click test.
    let shortcutTargets = FloorSelection()
    /// Click tests only: the shortcut the recorder produced (side effects off: nothing is saved).
    @Published private(set) var recordedShortcut: Shortcut?

    /// A new shortcut, or nil to turn it off.
    func setShortcut(_ shortcut: Shortcut?) {
        guard sideEffects else { recordedShortcut = shortcut; return }
        // Taken by another app: keep the old one.
        if let shortcut, !HotKeyCenter.shared.register(shortcut) {
            shortcutTaken = true
            HotKeyCenter.shared.register(settings.shortcut)
            return
        }
        shortcutTaken = false
        do { try config.set(shortcut?.string ?? "", at: ["shortcut"]) } catch let e as ConfigError { configError = e.message } catch {}
        settings = config.config
    }

    /// ClaudeBar's usage log; renders read CLAUDEBAR_RENDER_USAGE_HISTORY=<jsonl file> instead (never written).
    @Published private(set) var usageHistory = UsageHistory()
    /// Warned once per usage window; the windows warned about are kept (a preference) so a restart doesn't warn again.
    static let usageWarnedKey = "usageWarned"
    private lazy var usageWarner = UsageWarner(warned: sideEffects ? UserDefaults.standard.stringArray(forKey: Self.usageWarnedKey) ?? [] : [])
    private var usageHistoryLoaded = false

    /// The week chart under the usage bars is open; folded each time the dropdown opens (acknowledge).
    /// CLAUDEBAR_RENDER_USAGE_WEEK=1 opens it for renders.
    @Published var usageWeekShown = ProcessInfo.processInfo.environment["CLAUDEBAR_RENDER_USAGE_WEEK"] == "1"

    /// The line under the usage bars.
    var usageForecast: UsageForecast? { UsageForecast.headline(history: usageHistory.samples, now: Date()) }

    /// Notes the usage reading in the log (on change, at most once a minute), and warns once per window when the pace
    /// reaches a limit before its reset.
    private func recordUsage(_ usage: UsageSummary) {
        if !usageHistoryLoaded {
            usageHistoryLoaded = true
            if !sideEffects, let file = ProcessInfo.processInfo.environment["CLAUDEBAR_RENDER_USAGE_HISTORY"] {
                usageHistory = UsageHistory.load(URL(fileURLWithPath: file))
                return
            }
            usageHistory = UsageHistory.load(UsageHistory.defaultFile)
        }
        guard sideEffects else { return }
        let now = Date()
        if let sample = UsageSample(usage: usage, at: usage.asOf ?? now), usageHistory.add(sample) {
            try? usageHistory.save(UsageHistory.defaultFile)
        }
        if settings.usageWarnings, !isQuiet, let f = usageForecast, usageWarner.shouldWarn(f) {
            UserDefaults.standard.set(usageWarner.warnedKeys, forKey: Self.usageWarnedKey)
            notifier.post(title: "Usage", body: f.warning(time: Self.usageTime))
        }
    }

    /// "3:40 PM" today, else "Fri 2:00 PM".
    static func usageTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(d) ? "h:mm a" : "EEE h:mm a"
        return f.string(from: d)
    }

    /// A cat sound for `event`, if its switch is on and the spacing allows (SoundGate).
    func playSound(_ event: SoundEvent) {
        guard sideEffects, !isQuiet else { return }
        if case .clicked = event, !officeVisible { return }
        if case .elevator = event, !officeVisible { return }
        guard let sound = soundGate.sound(for: event, settings: settings.sounds, now: Date()) else { return }
        soundPlayer.play(sound, volume: settings.sounds.volume)
    }

    func setSound(_ key: String, _ on: Bool) {
        setSetting(on, at: ["sounds", key])
        updateMusic()
    }

    /// The 🎵 button.
    func toggleMusic() { setSound("music", !settings.sounds.music) }

    /// The lofi loop plays while the office is on screen and the 🎵 button is on (OfficeMusic).
    func updateMusic() {
        guard sideEffects else { return }
        let play = !isQuiet && OfficeMusic.shouldPlay(on: settings.sounds.music, officeTab: officeTabShown, peekShownSince: peekShownSince, now: Date())
        lofi.set(playing: play, volume: OfficeMusic.volume(sounds: settings.sounds.volume))
    }

    func setSoundVolume(_ volume: Double) {
        do { try config.set(min(1, max(0, volume)), at: ["sounds", "volume"]) } catch let e as ConfigError { configError = e.message } catch {}
        settings = config.config
        updateMusic()
    }

    /// The volume slider plays a meow (outside the gate) so you hear the level you picked.
    func previewSound() { soundPlayer.play(.meow, volume: settings.sounds.volume) }

    func setOfficeLighting(_ lighting: OfficeLighting) {
        do { try config.set(lighting.rawValue, at: ["officeLighting"]) } catch let e as ConfigError { configError = e.message } catch {}
        settings = config.config
        applyLighting()
    }

    /// The office's ☀️/🌙 pill: the opposite of what's showing now.
    func toggleOfficeLighting() {
        setOfficeLighting(settings.officeLighting.toggled(systemDark: Self.systemDark))
    }

    /// Day or night for all of ClaudeBar; Auto follows the Mac. Popovers take their look from the menu bar, not
    /// the app, so StatusItemController applies `appearance` to the dropdown and the peek as well.
    @Published private(set) var appearance: NSAppearance?

    func applyLighting() {
        let lighting = settings.officeLighting
        let target: NSAppearance? = lighting == .auto ? nil : NSAppearance(named: lighting == .night ? .darkAqua : .aqua)
        if NSApp.appearance?.name != target?.name { NSApp.appearance = target }
        if appearance?.name != target?.name { appearance = target }
    }

    /// The Mac's own appearance (ignoring ClaudeBar's override).
    private static var systemDark: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    func setSetup(_ s: SetupSettings) {
        do {
            try config.set(s.seen, at: ["setup", "seen"])
            if let state = s.state { try config.set(state.rawValue, at: ["setup", "state"]) }
        } catch let e as ConfigError { configError = e.message } catch {}
        settings = config.config
    }

    func setCatOfficeDir(_ dir: String?) {
        guard let dir else { return }
        do { try config.set(dir, at: ["catOffice", "dir"]) } catch let e as ConfigError { configError = e.message } catch {}
        settings = config.config
    }

    /// From before onboarding existed: a working setup counts as done, so its window doesn't open by itself.
    func inferSetupIfNeeded(env: SetupEnvironment = .real) async -> Bool {
        guard !settings.setup.seen else { return false }
        // The configured folder, else the one last seen running (as starting Cat Office uses).
        let inferred = await SetupSettings.inferred(
            configured: settings.catOffice.dir, remembered: UserDefaults.standard.string(forKey: Self.rememberedDirKey),
            bridgeDir: SetupActions.runningDir(env: env), statusLine: SetupActions.statusLine(env: env).state(),
            patched: { await SetupActions.isPatched($0, env: env) })
        // The setup window may have been opened (and finished or skipped) during the await.
        guard !settings.setup.seen else { return false }
        if let inferred { setSetup(inferred) }
        return SetupSettings.opensByItself(settings.setup, inferred: inferred)
    }

    private func setSetting(_ value: Bool, at path: [String]) {
        do { try config.set(value, at: path) } catch let e as ConfigError { configError = e.message } catch {}
        settings = config.config
        updateMirror()
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

    // MARK: Sessions: jump, answer, today's recap

    /// Cat Office on this agent's panel (`<base>/?agent=<id>`; the patched page opens its drawer, on its floor).
    func openInCatOffice(_ agent: OfficeAgent) {
        guard sideEffects, var c = URLComponents(url: officeClient.baseURL, resolvingAgainstBaseURL: false) else { return }
        c.queryItems = [URLQueryItem(name: "agent", value: agent.id)]
        NSWorkspace.shared.open(c.url ?? officeClient.baseURL)
    }

    /// Each pid's tty and the app it belongs to, looked up at most every 10 s (hovering a card asks often); pruned of
    /// old entries as it goes.
    private var ttys: [Int32: (tty: String?, host: TerminalHost?, at: Date)] = [:]

    private func terminal(of pid: Int32) -> (tty: String, host: TerminalHost)? {
        let now = Date()
        if let known = ttys[pid], now.timeIntervalSince(known.at) < 10 {
            return known.tty.flatMap { t in known.host.map { (t, $0) } }
        }
        ttys = ttys.filter { now.timeIntervalSince($0.value.at) < 60 }
        let tty = TerminalFinder.tty(of: pid)
        let host = tty == nil ? nil : TerminalFinder.host(of: pid)
        ttys[pid] = (tty, host, now)
        return tty.flatMap { t in host.map { (t, $0) } }
    }

    /// "Show terminal" is offered: the session's process has a tty, and Terminal or iTerm is running.
    func canShowTerminal(_ agent: OfficeAgent) -> Bool {
        // Renders only (CLAUDEBAR_RENDER_TERMINAL=1, or =missed for "couldn't bring it forward"): the link shows.
        if renderTerminal != nil { return true }
        guard let pid = agent.pid, let found = terminal(of: pid) else { return false }
        return TerminalFinder.terminalsRunning.contains(found.host.bundleId)
    }

    private var renderTerminal: String? { sideEffects ? nil : ProcessInfo.processInfo.environment["CLAUDEBAR_RENDER_TERMINAL"] }

    private static let terminalQueue = DispatchQueue(label: "ClaudeBar.terminal")

    /// Agents whose terminal tab couldn't be brought forward (not found, or macOS didn't allow ClaudeBar to ask).
    @Published private(set) var terminalMissed: Set<String> = []

    /// Brings forward the Terminal / iTerm tab the session runs in.
    func showTerminal(_ agent: OfficeAgent) {
        guard sideEffects, let pid = agent.pid, let found = terminal(of: pid) else { return }
        let id = agent.id
        // Off the main thread: macOS may first ask to let ClaudeBar control Terminal / iTerm.
        Self.terminalQueue.async {
            let shown = TerminalFinder.show(tty: found.tty, in: found.host)
            DispatchQueue.main.async {
                if shown { self.terminalMissed.remove(id) } else { self.terminalMissed.insert(id) }
            }
        }
    }

    /// Answers sent from ClaudeBar, by agent id; cleared when the agent stops waiting or waits on something else.
    @Published var answerState: [String: AnswerState] = [:]
    /// Click tests only (side effects off): the answer that would have been sent, never sent.
    @Published private(set) var lastAnswerRequest: (id: String, body: Data)?

    /// One ticket per click: only the latest click's send sets the agent's state.
    private var answerTickets = AnswerTickets()

    /// Sends `button`'s answer to Cat Office for `agent` (POST /__agents/<id>/answer), only while the agent still waits
    /// on `prompt`, the one the button was built from (Cat Office checks it again through the request's `expect`).
    func answer(_ agent: OfficeAgent, _ button: AnswerButton, prompt: PendingPrompt) {
        let id = agent.id
        guard answerState[id] != .sending else { return }
        if let changed = AnswerChoices.changed(prompt, agentId: id, in: office?.agents ?? []) {
            showBriefly(id, .failed(changed))
            return
        }
        let ticket = answerTickets.issue(for: id)
        guard sideEffects else {
            lastAnswerRequest = (id, button.request)
            markSent(id)
            return
        }
        guard let bridge = officeClient.bridge else {
            answerState[id] = .failed(AnswerChoices.refusal(status: nil, error: nil))
            return
        }
        answerState[id] = .sending
        Task { @MainActor in
            let refusal = await CatOfficeActions.answer(button.request, agentId: id, bridge: bridge)
            // A newer click owns the state now, or the prompt changed or closed meanwhile (that state was cleared):
            // don't bring back a stale one.
            guard answerTickets.isLatest(ticket, for: id), answerState[id] == .sending else { return }
            if let refusal { answerState[id] = .failed(refusal) } else { markSent(id) }
        }
    }

    /// `state` for `id` for a few seconds (the prompt changed under the click): then the new prompt's buttons show.
    private func showBriefly(_ id: String, _ state: AnswerState) {
        answerState[id] = state
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.answerState[id] == state else { return }
            self.answerState[id] = nil
        }
    }

    /// "Sent" for `id`; if the session still waits on the same prompt AnswerReset.sentFor later (the dialog didn't take
    /// it, or the next prompt is the same), the buttons come back.
    private func markSent(_ id: String) {
        let at = Date()
        answerState[id] = .sent(at: at)
        DispatchQueue.main.asyncAfter(deadline: .now() + AnswerReset.sentFor + 0.1) { [weak self] in
            // A changed prompt or a session no longer waiting has cleared it already (officeUpdated).
            guard let self, self.answerState[id] == .sent(at: at), AnswerReset.sentIsStale(sentAt: at, now: Date()) else { return }
            self.answerState[id] = nil
        }
    }

    /// Renders and click tests: the agent CLAUDEBAR_RENDER_WAITING made wait, and the cat whose hover card shows
    /// without a pointer (CLAUDEBAR_RENDER_CARD=1, or set by --test-answer).
    private(set) var renderWaitingId: String?
    @Published var renderCardAgent: String?
    private var renderAnswerApplied = false

    /// Renders only: CLAUDEBAR_RENDER_ANSWER=<sending|sent|failed> for the waiting agent; CLAUDEBAR_RENDER_CARD=1 shows
    /// its card (CLAUDEBAR_RENDER_CARD=<id, name or project> another agent's).
    private func renderAnswerState() {
        let env = ProcessInfo.processInfo.environment
        guard !sideEffects, !renderAnswerApplied, let card = env["CLAUDEBAR_RENDER_CARD"] ?? (renderWaitingId != nil ? "" : nil) else { return }
        if card != "1", !card.isEmpty {
            renderAnswerApplied = true
            renderCardAgent = office?.agents.first { [$0.id, $0.name, $0.repoName, $0.label].contains(card) }?.id
            if renderTerminal == "missed", let id = renderCardAgent { terminalMissed.insert(id) }
            return
        }
        guard let id = renderWaitingId else { return }
        renderAnswerApplied = true
        if card == "1" { renderCardAgent = id }
        switch env["CLAUDEBAR_RENDER_ANSWER"] {
        case "sending": answerState[id] = .sending
        case "sent": answerState[id] = .sent(at: Date())
        case "failed": answerState[id] = .failed(AnswerChoices.refusal(status: 409, error: nil))
        default: break
        }
    }

    /// The agent the render seam makes wait: the first office worker, else the first agent. With
    /// CLAUDEBAR_RENDER_WAITING_EXTERNAL=1, a stand-in session in an Orca terminal (the answerable kind) added for the
    /// render; =noterm, the same in another terminal (not answerable: no buttons).
    private static func renderWaitingIndex(_ agents: inout [OfficeAgent]) -> Int? {
        if let external = ProcessInfo.processInfo.environment["CLAUDEBAR_RENDER_WAITING_EXTERNAL"], external == "1" || external == "noterm" {
            var a = OfficeAgent(id: "render-external-0001", name: "orca-terminal", owner: "external", status: .waiting,
                                cwd: agents.first?.cwd ?? "/tmp", repoName: agents.first?.repoName, task: "Wire the answer buttons",
                                lastAction: "Bash: npm run build", sessionId: "render-external-0001")
            a.cat = agents.first?.cat
            a.orcaTerminal = external == "1" ? "term_render" : nil
            agents.append(a)
            return agents.count - 1
        }
        return agents.firstIndex { $0.isOffice && !$0.isSubagent && $0.status != .ended } ?? agents.indices.first
    }

    /// A sample prompt of each kind, for renders and the answer click test.
    private static func samplePrompt(_ kind: String) -> PendingPrompt? {
        switch kind {
        case "permission":
            return .permission(tool: "Bash", input: "npm run build && npm test -- --watch=false --reporter=dot src/agents/live")
        case "question":
            return .question([.init(question: "Which store should the recap read from?", header: "Store", multiSelect: false, options: [
                .init(label: "The session log", description: "~/.claude/claude-bar/sessions-today.jsonl, kept 2 days"),
                .init(label: "Cat Office's feed", description: "Only what the office saw since it started"),
                .init(label: "Both", description: ""),
            ])])
        case "plan":
            return .plan("# Add today's recap to Projects\n\n1. Log working spans\n2. Sum them since midnight\n3. Show the line")
        default:
            return nil
        }
    }

    /// ClaudeBar's log of sessions starting and stopping work (published when it gains events).
    @Published private(set) var sessionLog = SessionLog()
    private var sessionLogWorking = SessionLog()
    private var sessionLogLoaded = false
    static let sessionLogSeenKey = "sessionLogLastSeen"
    private var sessionLogSeenWritten: Date?

    /// The Mac is going to sleep: working time stops now, not when ClaudeBar next looks.
    func macWillSleep() {
        guard sideEffects, sessionLogLoaded else { return }
        sessionLogWorking.pause(at: Date())
        sessionLog = sessionLogWorking
        try? sessionLogWorking.save(SessionLog.defaultFile)
    }

    /// Today so far, for the top of Projects.
    var todayRecap: TodayRecap { TodayRecap.of(sessionLog, now: Date(), calendar: .current) }

    /// Notes who started or stopped working; saved when something changed. Renders read
    /// CLAUDEBAR_RENDER_SESSIONS=<jsonl file> instead (never written).
    private func recordSessions(_ tracked: [TrackedSession], fallback: [LiveSession]) {
        if !sessionLogLoaded {
            sessionLogLoaded = true
            if sideEffects {
                let seen = UserDefaults.standard.object(forKey: Self.sessionLogSeenKey) as? Date
                sessionLogWorking = SessionLog.load(SessionLog.defaultFile, lastUpdate: seen)
            } else if let file = ProcessInfo.processInfo.environment["CLAUDEBAR_RENDER_SESSIONS"] {
                sessionLogWorking = SessionLog.load(URL(fileURLWithPath: file))
            }
            sessionLog = sessionLogWorking
        }
        let entries = SessionLog.entries(tracked: tracked, agents: office?.agents ?? [], fallback: fallback)
        let changed = sessionLogWorking.update(entries, now: Date())
        // Heartbeat: when ClaudeBar last watched, so a restart after a long quiet stretch still counts it (at most
        // every 30 s; no file write).
        if sideEffects, let seen = sessionLogWorking.lastUpdate,
           sessionLogSeenWritten.map({ seen.timeIntervalSince($0) >= 30 }) ?? true {
            sessionLogSeenWritten = seen
            UserDefaults.standard.set(seen, forKey: Self.sessionLogSeenKey)
        }
        guard changed else { return }
        sessionLog = sessionLogWorking
        if sideEffects { try? sessionLogWorking.save(SessionLog.defaultFile) }
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

/// Minutes left at each cat's spot (agent id or spare key → whole minutes), published only when one shown changes.
final class MinutesLeft: ObservableObject {
    @Published var byCat: [String: Double] = [:]
}
