import AppKit
import ClaudeBarCore

/// The undo window's state. Nothing on disk changes before `undo()` (Undo selected).
@MainActor
final class UndoModel: ObservableObject {
    enum Phase { case loading, choose, done }

    @Published var phase: Phase = .loading
    @Published var rows: [UndoRow] = []
    @Published var ticked: Set<UndoRow.Kind> = []
    @Published var working = false
    @Published var results: [UndoRow.Kind: StepResult] = [:]
    @Published var doneLines: [String] = []
    /// Cat Office was running from the unpatched folder: Done offers Restart.
    @Published var needsRestart = false
    @Published var somethingAnswers = false
    /// Why Restart Cat Office did not work (shown under the button).
    @Published var restartError: String?

    let state: AppState
    let env: SetupEnvironment
    /// The Cat Office folder ClaudeBar knows (configured, else the one last seen running).
    let dir: String?
    var onClose: (() -> Void)?

    init(state: AppState, env: SetupEnvironment) {
        self.state = state
        self.env = env
        dir = CatOfficeDiscovery.folderToStart(configured: state.settings.catOffice.dir, remembered: env.rememberedDir())
    }

    /// Reads what's in place (off the main thread's way: the script runs detached).
    func load() async {
        rows = await UndoActions.rows(dir: dir, env: env)
        ticked = UndoPlan.startTicks(rows)
        somethingAnswers = await env.answers(state.settings.catOffice.url)
        phase = .choose
    }

    var runningHere: Bool {
        guard let dir, let running = SetupActions.runningDir(env: env) else { return false }
        return Paths.normalize(running) == Paths.normalize(dir)
    }

    var bridgeNamesAnotherFolder: Bool {
        guard let dir, let running = SetupActions.runningDir(env: env) else { return false }
        return Paths.normalize(running) != Paths.normalize(dir)
    }

    var warning: String? {
        UndoPlan.warning(unpatch: ticked.contains(.unpatch), runningHere: runningHere, somethingAnswers: somethingAnswers,
                         bridgeNamesAnotherFolder: bridgeNamesAnotherFolder)
    }

    func binding(_ kind: UndoRow.Kind) -> Bool { ticked.contains(kind) }
    func set(_ kind: UndoRow.Kind, _ on: Bool) { if on { ticked.insert(kind) } else { ticked.remove(kind) } }

    func undo() async {
        guard !working, !ticked.isEmpty else { return }
        working = true
        defer { working = false }
        let wasRunning = runningHere || (somethingAnswers && !bridgeNamesAnotherFolder)
        results = await UndoActions.run(ticked, dir: dir, env: env)
        if results[.remove] == nil {
            // After "Also remove" (even partly), ClaudeBar's settings are in the Trash: writing them would make a new file.
            state.setSetup(UndoPlan.setupAfter(state.settings.setup, unpatched: results[.unpatch]?.ok == true,
                                               statusLineRestored: results[.statusLine]?.ok == true))
        }
        needsRestart = results[.unpatch]?.ok == true && wasRunning && results[.remove]?.ok != true
        doneLines = UndoText.doneLines(results: results.mapValues(\.ok), leftOut: UndoPlan.leftOut(rows: rows, ticked: ticked))
        phase = .done
    }

    func restart() async {
        guard let dir else { return }
        working = true
        defer { working = false }
        if case .failed(let message) = await SetupActions.restartCatOffice(dir, env: env, settings: state.settings.catOffice) {
            restartError = "Restarting Cat Office didn't work: \(message)"
        } else {
            restartError = nil
            needsRestart = false
        }
    }

    /// Removal ran (even partly): ClaudeBar quits when the window closes.
    var removed: Bool { results[.remove] != nil }

    func close() { onClose?() }
    func quit() { NSApp.terminate(nil) }
}
