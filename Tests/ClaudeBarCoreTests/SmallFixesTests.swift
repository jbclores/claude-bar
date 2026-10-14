import CoreGraphics
import Foundation
import Testing
@testable import ClaudeBarCore

/// "Show terminal" only for Terminal and iTerm: the app that owns the session's terminal, from its process's ancestors.
@Suite struct TerminalHostTests {
    @Test func findsTerminalOrITermAndNothingElse() {
        #expect(TerminalHost.of(ancestorCommands: ["claude", "-zsh", "login -pf me",
                                                    "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"]) == .terminal)
        #expect(TerminalHost.of(ancestorCommands: ["claude", "-zsh", "/Applications/iTerm.app/Contents/MacOS/iTerm2"]) == .iterm)
        #expect(TerminalHost.of(ancestorCommands: ["claude", "/bin/zsh -il",
                                                    "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper (Plugin).app/Contents/MacOS/Code Helper (Plugin)",
                                                    "/Applications/Visual Studio Code.app/Contents/MacOS/Electron"]) == nil)
        #expect(TerminalHost.of(ancestorCommands: []) == nil)
        #expect(TerminalHost.terminal.bundleId == "com.apple.Terminal" && TerminalHost.iterm.bundleId == "com.googlecode.iterm2")
    }
}

/// The usage warning remembers which windows it warned about, so a restart doesn't warn again.
@Suite struct UsageWarnerMemoryTests {
    @Test func aRestartDoesNotWarnTwiceForOneWindow() throws {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let risky = UsageForecast(window: .fiveHour, projected: 100, hitAt: t0.addingTimeInterval(600), resetsAt: t0.addingTimeInterval(3600))
        var first = UsageWarner()
        let warned = first.shouldWarn(risky)
        #expect(warned)
        var restarted = UsageWarner(warned: first.warnedKeys)
        let again = restarted.shouldWarn(risky)
        #expect(!again)
        var later = risky
        later.resetsAt = t0.addingTimeInterval(7 * 3600)
        let next = restarted.shouldWarn(later)
        #expect(next, "a new window warns again")
        // Only recent windows are kept (the last 20).
        var many = UsageWarner()
        for i in 0..<30 {
            var f = risky
            f.resetsAt = t0.addingTimeInterval(Double(i) * 3600)
            _ = many.shouldWarn(f)
        }
        #expect(many.warnedKeys.count == 20)
    }
}

/// The floor menu lists floors top first, as Cat Office's does (12 … 1).
@Suite struct FloorMenuOrderTests {
    @Test func topFloorFirst() {
        let floors = [1, 2, 12, 3].map { Floor(id: $0, name: "f\($0)", repoRoot: nil, floorTexture: nil, wallTexture: nil, desks: [],
                                               elevator: nil, hasLoungeSign: false) }
        #expect(Building(floors: floors, catHeight: nil).menuOrder.map(\.id) == [12, 3, 2, 1])
    }
}

/// Small cat pictures keep the cat's own proportions (cats.json canvas).
@Suite struct CatFrameSizeTests {
    @Test func heightFollowsTheCanvas() {
        #expect(abs(CatFrame.standard.size(width: 70).height - 70 * 380 / 360) < 0.001)
        let tall = CatFrame(canvas: CGSize(width: 200, height: 400), feet: CGPoint(x: 100, y: 380), bodyHeight: 300)
        #expect(tall.size(width: 40) == CGSize(width: 40, height: 80))
    }
}

/// The recap: the Mac going to sleep stops working time at that moment; a few quiet minutes (App Nap slowing ClaudeBar's
/// timer) don't split a span.
@Suite struct SessionLogSleepTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    func at(_ m: Double) -> Date { t0.addingTimeInterval(m * 60) }

    @Test func sleepStopsWorkAtTheMomentItStarts() {
        var log = SessionLog()
        for m in stride(from: 0, through: 30, by: 10) { _ = log.update([("a", "p", .working)], now: at(Double(m))) }
        log.pause(at: at(31))                                    // the Mac goes to sleep
        _ = log.update([("a", "p", .working)], now: at(31 + 600)) // wakes 10 h later
        #expect(log.events.map(\.working) == [true, false, true])
        #expect(log.events[1].at == at(31) && !log.events[1].finished)
        #expect(log.events[2].at == at(631))
    }

    @Test func aFewQuietMinutesDoNotSplitASpan() {
        var log = SessionLog()
        _ = log.update([("a", "p", .working)], now: at(0))
        _ = log.update([("a", "p", .working)], now: at(6))      // App Nap: 6 minutes between updates
        _ = log.update([("a", "p", .working)], now: at(14))
        #expect(log.events.count == 1, "still one working span")
    }
}
