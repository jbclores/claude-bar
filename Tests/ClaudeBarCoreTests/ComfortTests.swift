import Foundation
import Testing
@testable import ClaudeBarCore

/// Quiet hours: no sounds or notifications from `from` to `to` (across midnight), all weekend if ticked, or for an
/// hour on request.
@Suite struct QuietHoursTests {
    var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    /// 2027-01-15 is a Friday.
    func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2027, month: 1, day: day, hour: h, minute: m))!
    }
    let evening = QuietHours(on: true, from: 19 * 60, to: 8 * 60, weekends: false)

    @Test func acrossMidnightWithExactEdges() {
        #expect(!evening.isQuiet(at: at(15, 18, 59), calendar: utc))
        #expect(evening.isQuiet(at: at(15, 19, 0), calendar: utc), "from is inclusive")
        #expect(evening.isQuiet(at: at(16, 3), calendar: utc))
        #expect(!evening.isQuiet(at: at(15, 8, 0), calendar: utc), "to is exclusive")
        #expect(!evening.isQuiet(at: at(15, 12), calendar: utc))
        var off = evening
        off.on = false
        #expect(!off.isQuiet(at: at(15, 22), calendar: utc))
    }

    @Test func sameDaySpanAndWeekends() {
        let lunch = QuietHours(on: true, from: 12 * 60, to: 13 * 60, weekends: false)
        #expect(lunch.isQuiet(at: at(15, 12, 30), calendar: utc) && !lunch.isQuiet(at: at(15, 13, 0), calendar: utc))
        var weekends = evening
        weekends.weekends = true
        #expect(weekends.isQuiet(at: at(16, 12), calendar: utc), "Saturday noon")
        #expect(weekends.isQuiet(at: at(17, 23), calendar: utc), "Sunday night")
        #expect(!weekends.isQuiet(at: at(18, 12), calendar: utc), "Monday noon")
    }

    @Test func quietForAnHourAndWhenItEnds() {
        let off = QuietHours(on: false, from: 19 * 60, to: 8 * 60, weekends: false)
        let until = at(15, 15, 40)
        #expect(off.isQuiet(at: at(15, 15, 0), calendar: utc, quietUntil: until))
        #expect(!off.isQuiet(at: at(15, 15, 40), calendar: utc, quietUntil: until))
        #expect(off.quietEnds(at: at(15, 15, 0), calendar: utc, quietUntil: until) == until)
        #expect(evening.quietEnds(at: at(15, 22), calendar: utc) == at(16, 8))
        #expect(evening.quietEnds(at: at(15, 12), calendar: utc) == nil)
        var weekends = evening
        weekends.weekends = true
        #expect(weekends.quietEnds(at: at(16, 12), calendar: utc) == at(18, 8), "the weekend runs into Monday morning's quiet hours")
    }

    @Test func parsesFromConfig() throws {
        let c = try Config.parse(Data(#"{"projects":[],"quietHours":{"on":true,"from":"21:30","to":"07:15","weekends":true}}"#.utf8))
        #expect(c.quietHours == QuietHours(on: true, from: 21 * 60 + 30, to: 7 * 60 + 15, weekends: true))
        #expect(Config.empty.quietHours == QuietHours.standard)
        #expect(!QuietHours.standard.on && QuietHours.standard.from == 19 * 60 && QuietHours.standard.to == 8 * 60)
        #expect(QuietHours.clock(21 * 60 + 30) == "21:30")
    }
}

/// The shortcut that opens ClaudeBar: stored as "ctrl+opt+C", shown as "⌃⌥C".
@Suite struct ShortcutTests {
    @Test func parsesShowsAndWrites() throws {
        let s = try #require(Shortcut(string: "ctrl+opt+C"))
        #expect(s.display == "⌃⌥C")
        #expect(s.string == "ctrl+opt+C")
        #expect(Shortcut.standard == s)
        #expect(Shortcut(string: "cmd+shift+space")?.display == "⇧⌘Space")
        #expect(Shortcut(string: "C") == nil, "needs a modifier")
        #expect(Shortcut(string: "ctrl+opt+nope") == nil)
        #expect(Shortcut(string: "shift+C") == nil, "shift alone is too easy to hit")
    }

    @Test func fromAKeyPress() {
        // Carbon key code 8 is C.
        let s = Shortcut(keyCode: 8, control: true, option: true, shift: false, command: false)
        #expect(s?.string == "ctrl+opt+C")
        #expect(Shortcut(keyCode: 8, control: false, option: false, shift: false, command: false) == nil)
        #expect(Shortcut(keyCode: 999, control: true, option: false, shift: false, command: false) == nil, "unknown key")
    }

    @Test func configKeepsItOrTurnsItOff() throws {
        #expect(Config.empty.shortcut == .standard)
        #expect(try Config.parse(Data(#"{"projects":[],"shortcut":"cmd+opt+K"}"#.utf8)).shortcut?.display == "⌥⌘K")
        #expect(try Config.parse(Data(#"{"projects":[],"shortcut":""}"#.utf8)).shortcut == nil, "turned off")
    }

    @Test func talkStandardShortcut() {
        #expect(Shortcut.talkStandard.display == "⌃⌥V")
        #expect(Shortcut.talkStandard.keyCode == 9)
    }
}
