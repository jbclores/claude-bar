import AppKit
import ClaudeBarCore

struct StepResult: Equatable { var ok: Bool; var text: String }

/// The setup window's state: which step, what was found and chosen, and what each setup action did.
/// Nothing on disk changes before `connect()` (Continue on the Connect step).
@MainActor
final class SetupModel: ObservableObject {
    enum Step: Int, CaseIterable { case welcome, find, connect, done }

    @Published var step: Step = .welcome
    @Published var candidates: [CatOfficeCandidate] = []
    @Published var chosen: String?
    @Published var choiceError: String?
    @Published var searching = false
    @Published var patch = true
    @Published var usage = true
    @Published var start = true
    @Published var keepOwnStatusLine = true
    @Published var working = false
    @Published var results: [String: StepResult] = [:]
    /// Cat Office is running and the patch changed it: the Done step offers Restart.
    @Published var needsRestart = false
    @Published private(set) var statusLine: StatusLineState = .none

    let state: AppState
    let env: SetupEnvironment
    var onClose: (() -> Void)?
    var onOpenOffice: (() -> Void)?

    init(state: AppState, env: SetupEnvironment) {
        self.state = state
        self.env = env
        statusLine = SetupActions.statusLine(env: env).state()
    }

    /// The chosen copy is the one running now (its bridge file names it).
    var running: Bool { candidates.contains { $0.path == chosen && $0.running } }

    /// Looks for Cat Office off the main thread (the usual places can be slow, and macOS may ask for folder access).
    func find() async {
        step = .find
        searching = true
        defer { searching = false }
        let running = SetupActions.runningDir(env: env)
        let saved = state.settings.catOffice.dir
        let roots = CatOfficeFinder.defaultRoots(home: env.home.path)
        candidates = await Task.detached { CatOfficeFinder.candidates(running: running, saved: saved, roots: roots) }.value
        chosen = candidates.first?.path
    }

    func choose(_ path: String) -> Bool {
        let real = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        guard CatOfficeFinder.isCatOffice(real) else { choiceError = "That folder isn't Cat Office."; return false }
        choiceError = nil
        if !candidates.contains(where: { $0.path == real }) {
            candidates.insert(CatOfficeCandidate(path: real, modified: Date(), running: false), at: 0)
        }
        chosen = real
        return true
    }

    func useNoCatOffice() {
        chosen = nil
        patch = false; start = false
        step = .connect
    }

    func connect() async {
        working = true
        defer { working = false }
        results = [:]
        needsRestart = false
        var patched: Bool? = nil
        var patchChanged = false
        if let dir = chosen {
            state.setCatOfficeDir(dir)
            if patch {
                switch await SetupActions.patch(dir, env: env) {
                case .patched:
                    results["patch"] = StepResult(ok: true, text: "Patched (a backup of the changed files is in .cat-office/).")
                    patched = true; patchChanged = true
                case .alreadyPatched: results["patch"] = StepResult(ok: true, text: "Already patched."); patched = true
                case .notCatOffice: results["patch"] = StepResult(ok: false, text: "That folder isn't Cat Office.")
                case .doesNotFit:
                    results["patch"] = StepResult(ok: false, text: "Your Cat Office version isn't supported for the extras. Nothing was changed.")
                    patched = false
                case .failed(let why): results["patch"] = StepResult(ok: false, text: "The patch didn't run: \(why)")
                }
            } else {
                patched = await SetupActions.isPatched(dir, env: env)
            }
        }
        if usage {
            let line = SetupActions.statusLine(env: env)
            do {
                switch line.state() {
                case .claudeBar:
                    results["usage"] = StepResult(ok: true, text: "ClaudeBar's status line is already set up.")
                case .none:
                    try line.useClaudeBar()
                    results["usage"] = StepResult(ok: true, text: "ClaudeBar's status line is on.")
                case .own:
                    if keepOwnStatusLine {
                        try line.wrap()
                        results["usage"] = StepResult(ok: true, text: "Your status line is kept; ClaudeBar reads its data quietly.")
                    } else {
                        try line.useClaudeBar()
                        results["usage"] = StepResult(ok: true, text: "ClaudeBar's status line is on (yours is backed up).")
                    }
                case .wrapped:
                    // Already kept: nothing to change. (Switching to ClaudeBar's is offered only for `.own`.)
                    results["usage"] = StepResult(ok: true, text: "Your status line is kept; ClaudeBar reads its data quietly.")
                case .unreadable:
                    results["usage"] = StepResult(ok: false, text: "~/.claude/settings.json isn't valid JSON, so it was left alone. See the guide to add the status line by hand.")
                }
            } catch {
                results["usage"] = StepResult(ok: false, text: (error as? StatusLineError)?.message ?? error.localizedDescription)
            }
            statusLine = line.state()
        }
        if let dir = chosen {
            if running {
                results["start"] = StepResult(ok: true, text: patchChanged ? "Cat Office is running: restart it to load the patch." : "Cat Office is running.")
                needsRestart = patchChanged
            } else if start {
                if !SetupActions.hasNode() {
                    results["start"] = StepResult(ok: false, text: "Cat Office needs Node.js. Install it from nodejs.org, then start Cat Office.")
                } else {
                    var s = state.settings.catOffice; s.dir = dir
                    switch await CatOfficeLauncher().start(settings: s) {
                    case .started: results["start"] = StepResult(ok: true, text: "Cat Office is starting.")
                    case .alreadyRunning:
                        results["start"] = StepResult(ok: true, text: patchChanged ? "Cat Office is running: restart it to load the patch." : "Cat Office is running.")
                        needsRestart = patchChanged
                    case .notConfigured, .npmNotFound: results["start"] = StepResult(ok: false, text: "Cat Office needs Node.js. Install it from nodejs.org.")
                    case .failed(let why): results["start"] = StepResult(ok: false, text: "Cat Office didn't start: \(why)")
                    }
                }
            }
        }
        let setupState: SetupState = chosen == nil ? .noCatOffice : (patched == true ? .full : .reduced)
        state.setSetup(SetupSettings(seen: true, state: setupState))
        step = .done
    }

    /// Stops this folder's Cat Office dev server (ending Claude sessions inside it), then starts it again.
    func restart() async {
        guard let dir = chosen else { return }
        working = true
        defer { working = false }
        switch await SetupActions.restartCatOffice(dir, env: env, settings: state.settings.catOffice) {
        case .started, .alreadyRunning:
            results["start"] = StepResult(ok: true, text: "Cat Office restarted.")
            needsRestart = false
        case .failed(let why): results["start"] = StepResult(ok: false, text: "Cat Office didn't restart: \(why)")
        case .notConfigured, .npmNotFound: results["start"] = StepResult(ok: false, text: "Cat Office didn't restart: it needs Node.js.")
        }
    }

    func skip() {
        state.setSetup(SetupSettings(seen: true, state: state.settings.setup.state))
        onClose?()
    }

    func openOffice() {
        onClose?()
        onOpenOffice?()
    }

    /// Done's checklist: what each step did, and a line for each one skipped (what's missing, how to fix it).
    var summary: [(ok: Bool, text: String)] {
        var lines: [(ok: Bool, text: String)] = []
        if let dir = chosen {
            lines.append((true, "Cat Office: \(URL(fileURLWithPath: dir).lastPathComponent)"))
        } else {
            lines.append((false, "No Cat Office: the Office tab stays empty. Set it up any time from Settings."))
        }
        if let r = results["patch"] { lines.append((r.ok, r.text)) } else if chosen != nil {
            lines.append((false, "Not patched: cats may not match the browser and helpers don't show. Run setup again to patch."))
        }
        if let r = results["usage"] { lines.append((r.ok, r.text)) } else {
            lines.append((false, "Usage is off: run setup again, or see the guide to add the status line by hand."))
        }
        if let r = results["start"] { lines.append((r.ok, r.text)) }
        return lines
    }
}
