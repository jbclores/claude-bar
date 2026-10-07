import AppKit
import ClaudeBarCore
import Foundation

/// `ClaudeBar --undo [--remove]`: the undo window's rows in Terminal, a y/N question, then the same undo.
@MainActor
enum UndoCommand {
    static func run(remove: Bool) -> Never {
        setvbuf(stdout, nil, _IOLBF, 0)
        Task { @MainActor in exit(await main(remove: remove)) }
        dispatchMain()
    }

    static func main(remove: Bool) async -> Int32 {
        let testRoot = ProcessInfo.processInfo.environment["CLAUDEBAR_UNDO_ROOT"].map { URL(fileURLWithPath: $0) }
        var env = SetupEnvironment.real
        let config: ConfigStore
        if let root = testRoot {
            let home = root.appendingPathComponent("home")
            env.home = home
            env.claudeDir = home.appendingPathComponent(".claude")
            env.bridgeFile = root.appendingPathComponent("bridge.json")
            env.answers = { _ in false }
            env.launchAtLoginOff = { true }
            env.rememberedDir = { nil }
            config = ConfigStore(file: root.appendingPathComponent("projects.json"))
        } else {
            config = ConfigStore()
        }
        let settings = config.config
        let dir = CatOfficeDiscovery.folderToStart(configured: settings.catOffice.dir, remembered: env.rememberedDir())

        let rows = await UndoActions.rows(dir: dir, env: env)
        var ticked = UndoPlan.startTicks(rows)
        if remove { ticked.insert(.remove) }
        let running = SetupActions.runningDir(env: env)
        let runningHere = dir != nil && running.map(Paths.normalize) == dir.map(Paths.normalize)
        let another = dir != nil && running != nil && !runningHere
        let answers = await env.answers(settings.catOffice.url)
        let warning = UndoPlan.warning(unpatch: ticked.contains(.unpatch), runningHere: runningHere,
                                       somethingAnswers: answers, bridgeNamesAnotherFolder: another)
        print(UndoText.terminalList(rows: rows, ticked: ticked, warning: warning))
        print("")

        if remove, testRoot == nil, otherClaudeBarRunning() {
            print("Quit ClaudeBar first (click the cat in the menu bar, then Quit), then run this again.")
            print(UndoText.nothingChanged)
            return 1
        }
        guard !ticked.isEmpty else { print(UndoText.nothingChanged); return 0 }
        print(UndoText.question, terminator: "")
        let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased()
        guard answer == "y" || answer == "yes" else { print(""); print(UndoText.nothingChanged); return 0 }

        let results = await UndoActions.run(ticked, dir: dir, env: env)
        if results[.remove] == nil {
            let after = UndoPlan.setupAfter(settings.setup, unpatched: results[.unpatch]?.ok == true,
                                            statusLineRestored: results[.statusLine]?.ok == true)
            if let state = after.state, after != settings.setup { try? config.set(state.rawValue, at: ["setup", "state"]) }
        }
        print("")
        for kind in UndoRow.Kind.allCases {
            if let r = results[kind] { print("\(r.ok ? "✓" : "✗") \(r.text)") }
        }
        for line in UndoText.doneLines(results: results.mapValues(\.ok), leftOut: UndoPlan.leftOut(rows: rows, ticked: ticked)) { print(line) }
        if results[.unpatch]?.ok == true, runningHere || (answers && !another) {
            print("Cat Office was running: if it looks stuck, stop its dev server and run npm run dev again.")
        }
        return results.values.allSatisfy(\.ok) ? 0 : 1
    }

    /// Another ClaudeBar (the menu bar app) is running.
    static func otherClaudeBarRunning() -> Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        return NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .contains { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    }
}
