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

    func openHelpGuide() {
        guard let url = helpGuide else { return }
        NSWorkspace.shared.open(url)
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
        guard snapshot != office else { updateMirror(); return }
        let cameOnline = office == nil && snapshot != nil
        // Only the browser's places moved (every 2 s while a Cat Office page is shown): the mirror, not the status.
        let placesOnly = office.flatMap { old in snapshot.map(old.sameExceptPlaces) } ?? false
        office = snapshot
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
        if sideEffects {
            let now = Date()
            for event in finished {
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
        if catalog.cats != catalogCats {
            catalogCats = catalog.cats
            updateMirror()
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
    func setShowSpareCats(_ on: Bool) { setSetting(on, at: ["office", "spareCats"]) }

    /// A cat sound for `event`, if its switch is on and the spacing allows (SoundGate).
    func playSound(_ event: SoundEvent) {
        guard sideEffects else { return }
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
        let play = OfficeMusic.shouldPlay(on: settings.sounds.music, officeTab: officeTabShown, peekShownSince: peekShownSince, now: Date())
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
