import ClaudeBarCore
import Foundation
import ServiceManagement

/// Where setup reads and writes: the real Mac, or temp folders for the click test.
struct SetupEnvironment: Sendable {
    var home: URL
    var claudeDir: URL
    var resources: URL
    var bridgeFile: URL
    /// Apple's command line tools are installed (ClaudeBar's status line runs python3 and git).
    var toolsInstalled: @Sendable () -> Bool = { StatusLineSetup.commandLineToolsInstalled() }

    /// Something answers HTTP at Cat Office's address (injected so tests and renders never reach a real Cat Office).
    var answers: @Sendable (URL) async -> Bool = { await CatOfficeLauncher.answers($0) }

    /// "Also remove ClaudeBar" turns Launch at Login off (injected so tests never touch the real login item).
    /// Returns true when it is off afterwards.
    var launchAtLoginOff: @Sendable () -> Bool = {
        if SMAppService.mainApp.status == .enabled { try? SMAppService.mainApp.unregister() }
        return SMAppService.mainApp.status != .enabled
    }
    /// The Cat Office folder last seen running (injected so tests never find the real one and unpatch it).
    var rememberedDir: @Sendable () -> String? = { UserDefaults.standard.string(forKey: AppState.rememberedDirKey) }

    static var real: SetupEnvironment {
        let home = Paths.home
        return SetupEnvironment(home: home, claudeDir: home.appendingPathComponent(".claude"),
                                resources: Bundle.main.resourceURL!.appendingPathComponent("Setup"),
                                bridgeFile: CatOfficeDiscovery.bridgeFile)
    }
}

enum PatchOutcome: Equatable {
    case patched, alreadyPatched, notCatOffice
    case doesNotFit(String)
    case failed(String)
}

/// What each setup step does on disk: run the bundled scripts and Cat Office's launcher.
@MainActor
enum SetupActions {
    static func patch(_ dir: String, env: SetupEnvironment) async -> PatchOutcome {
        let script = env.resources.appendingPathComponent("patch-cat-office.sh").path
        let result = await run("/bin/bash", [script, dir], env: [
            "CAT_OFFICE_PATCH": env.resources.appendingPathComponent("cat-office.patch").path,
            "CAT_OFFICE_PATCH_HISTORY": env.resources.appendingPathComponent("patch-history").path,
        ])
        switch result.code {
        case 0: return result.output.hasPrefix("Already patched") ? .alreadyPatched : .patched
        case 2: return .notCatOffice
        case 3: return .doesNotFit(result.output)
        default: return .failed(result.output)
        }
    }

    /// Whether the bundled patch is applied: true when it reverses cleanly (a dry run, nothing changes), false when
    /// it doesn't but the folder is Cat Office, nil when the folder isn't Cat Office or the check can't run (patch
    /// missing, launch failure, or patch's exit 2: trouble).
    static func isPatched(_ dir: String, env: SetupEnvironment) async -> Bool? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir + "/package.json"), fm.fileExists(atPath: dir + "/server/agent-bridge") else { return nil }
        let patch = env.resources.appendingPathComponent("cat-office.patch").path
        guard fm.fileExists(atPath: patch) else { return nil }
        let result = await run("/bin/sh", ["-c", "patch -d \"$1\" -p1 -R --dry-run -s -f < \"$2\"", "sh", dir, patch], env: [:])
        switch result.code {
        case 0: return true
        case 1: return false
        default: return nil
        }
    }

    /// Stops this folder's Cat Office dev server (only its own node/npm processes), then starts it again.
    static func restartCatOffice(_ dir: String, env: SetupEnvironment, settings: CatOfficeSettings) async -> CatOfficeLauncher.Result {
        let stop = await run("/bin/bash", [env.resources.appendingPathComponent("stop-cat-office.sh").path, dir],
                             env: ["CAT_OFFICE_BRIDGE_FILE": env.bridgeFile.path])
        guard stop.code == 0 else { return .failed(stop.output) }
        var s = settings; s.dir = dir
        return await CatOfficeLauncher().start(settings: s)
    }

    static func statusLine(env: SetupEnvironment) -> StatusLineSetup {
        let script = (try? String(contentsOf: env.resources.appendingPathComponent("statusline-command.sh"), encoding: .utf8)) ?? ""
        return StatusLineSetup(claudeDir: env.claudeDir, script: script, toolsInstalled: env.toolsInstalled)
    }

    static func hasNode() -> Bool { CatOfficeLauncher.hasNode(home: NSHomeDirectory()) }

    /// The folder of the Cat Office running now. A stale bridge file (dead pid, or a pid reused by something that
    /// isn't node/npm) names nothing.
    static func runningDir(env: SetupEnvironment) -> String? {
        CatOfficeDiscovery.bridgeInfo(file: env.bridgeFile, isAlive: CatOfficeDiscovery.isCatOfficeProcess)?.dir
    }

    static func bridgeStamp(env: SetupEnvironment) -> BridgeStamp? {
        CatOfficeDiscovery.bridgeStamp(file: env.bridgeFile, isAlive: CatOfficeDiscovery.isCatOfficeProcess)
    }

    /// After patching a running Cat Office: waits up to `seconds` for it to reload by itself (Vite reloads when the
    /// patch changes its server files), i.e. for a new start's bridge naming `dir`.
    static func waitForReload(_ dir: String, before: BridgeStamp?, env: SetupEnvironment, seconds: Double = 5) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while true {
            if CatOfficeDiscovery.reloaded(before: before, after: bridgeStamp(env: env), dir: dir) { return true }
            guard Date() < deadline else { return false }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    struct Output { var code: Int32; var output: String }

    static func run(_ tool: String, _ args: [String], env extra: [String: String]) async -> Output {
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = args
            p.environment = ProcessInfo.processInfo.environment.merging(extra) { $1 }
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
            do { try p.run() } catch { return Output(code: -1, output: error.localizedDescription) }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return Output(code: p.terminationStatus, output: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }.value
    }
}
