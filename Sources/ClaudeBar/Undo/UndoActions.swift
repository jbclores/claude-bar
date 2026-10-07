import ClaudeBarCore
import Foundation

/// What undo does on disk, shared by the window and `ClaudeBar --undo`: in order, unpatch, the status line, remove.
@MainActor
enum UndoActions {
    static func script(_ env: SetupEnvironment) -> String { env.resources.appendingPathComponent("patch-cat-office.sh").path }

    static func scriptEnv(_ env: SetupEnvironment) -> [String: String] {
        ["CAT_OFFICE_PATCH": env.resources.appendingPathComponent("cat-office.patch").path,
         "CAT_OFFICE_PATCH_HISTORY": env.resources.appendingPathComponent("patch-history").path]
    }

    /// A dry run of the bundled script's --undo; changes nothing.
    static func check(_ dir: String?, env: SetupEnvironment) async -> UnpatchCheck {
        guard let dir else { return .unknown }
        let r = await SetupActions.run("/bin/bash", [script(env), "--undo", "--dry-run", dir], env: scriptEnv(env))
        switch r.code {
        case 0: return r.output.hasPrefix("Would unpatch") ? .patched : .notPatched
        case 3: return .cannotUndo
        default: return .unknown
        }
    }

    static func rows(dir: String?, env: SetupEnvironment) async -> [UndoRow] {
        let line = SetupActions.statusLine(env: env)
        return UndoPlan.rows(catOfficeDir: dir, unpatch: await check(dir, env: env), statusLine: line.state(),
                             canRestore: line.canRestore, home: env.home.path)
    }

    /// Runs the ticked rows in order; each result's text is what the window and Terminal show.
    static func run(_ ticked: Set<UndoRow.Kind>, dir: String?, env: SetupEnvironment) async -> [UndoRow.Kind: StepResult] {
        var results: [UndoRow.Kind: StepResult] = [:]
        if ticked.contains(.unpatch), let dir {
            let r = await SetupActions.run("/bin/bash", [script(env), "--undo", dir], env: scriptEnv(env))
            switch r.code {
            case 0 where r.output.hasPrefix("Unpatched"):
                results[.unpatch] = StepResult(ok: true, text: "Cat Office is unpatched (a backup of the changed files is in .cat-office/).")
            case 0:
                results[.unpatch] = StepResult(ok: true, text: "Cat Office wasn't patched, so there was nothing to undo.")
            case 3:
                results[.unpatch] = StepResult(ok: false, text: UndoText.failedSafe
                    + " ClaudeBar couldn't take its patch out cleanly; your backups are in \(dir)/.cat-office/.")
            default:
                results[.unpatch] = StepResult(ok: false, text: UndoText.failedSafe + " " + r.output)
            }
        }
        if ticked.contains(.statusLine) {
            do {
                let done = try SetupActions.statusLine(env: env).restore()
                results[.statusLine] = StepResult(ok: true, text: done.message)
            } catch {
                let message = (error as? StatusLineError)?.message ?? error.localizedDescription
                results[.statusLine] = StepResult(ok: false, text: UndoText.failedSafe + " " + UndoText.sentence(message)
                    + " See What ClaudeBar changes for how to do it by hand.")
            }
        }
        if ticked.contains(.remove) {
            let loginOff = env.launchAtLoginOff()
            let removal = ClaudeBarRemoval(home: env.home).remove()
            let loginHelp = "turn it off in System Settings → General → Login Items."
            switch (removal.failures.isEmpty, loginOff) {
            case (true, true):
                results[.remove] = StepResult(ok: true, text: "Launch at Login is off, and ClaudeBar's files are in the Trash.")
            case (true, false):
                results[.remove] = StepResult(ok: false, text: "ClaudeBar's files are in the Trash, but Launch at Login is still on: " + loginHelp)
            case (false, true):
                results[.remove] = StepResult(ok: false, text: "Some of ClaudeBar's files couldn't go to the Trash: " + removal.failures.joined(separator: "; "))
            case (false, false):
                results[.remove] = StepResult(ok: false, text: "Some of ClaudeBar's files couldn't go to the Trash: "
                    + removal.failures.joined(separator: "; ") + ". Launch at Login is still on: " + loginHelp)
            }
        }
        return results
    }
}
