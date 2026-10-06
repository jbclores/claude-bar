import AppKit
import ClaudeBarCore
import ServiceManagement

/// Everything the menu bar shows: files and git re-read every 5 seconds, Cat Office's feed as it arrives.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var output = StatusOutput.empty
    @Published private(set) var office: OfficeSnapshot?
    @Published private(set) var needsAttention = false
    @Published private(set) var statusSince: [String: Date] = [:]
    @Published private(set) var configError: String?
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    let config = ConfigStore()
    private let snapshots = SnapshotReader()
    private let sessions = LiveSessionReader()
    private let git = GitBranchReader()
    private let officeSettings = LockedBox(CatOfficeSettings())
    private(set) lazy var officeClient = CatOfficeClient(settings: officeSettings) { [weak self] snapshot in
        Task { @MainActor in self?.officeUpdated(snapshot) }
    }
    private let notifier = Notifier()
    private var tracker = AttentionTracker()
    private var files: StatusInput?
    private var timer: Timer?
    private var refreshing = false

    func start() {
        refresh()
        officeClient.start()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Re-reads the config, snapshots, sessions and branches (off the main thread), then rebuilds the rows.
    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        config.reload()
        configError = config.error
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
                           branches: branches, existing: existing)
    }

    private func filesRead(_ input: StatusInput) {
        files = input
        refreshing = false
        recompute()
    }

    private func officeUpdated(_ snapshot: OfficeSnapshot?) {
        guard snapshot != office else { return }
        office = snapshot
        recompute()
    }

    private func recompute() {
        guard var input = files else { return }
        input.office = office
        let tracked = StatusModel.trackedSessions(fallback: input.fallbackSessions, office: office)
        let finished = tracker.update(tracked, now: Date())
        if config.config.notifications { finished.forEach(notifier.post) }
        input.attention = tracker.attention
        input.statusSince = tracker.since
        statusSince = tracker.since
        needsAttention = !tracker.attention.isEmpty
        output = StatusModel.build(input)
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
