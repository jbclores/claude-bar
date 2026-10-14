import Foundation

/// Quiet hours: no ClaudeBar sounds or notifications from `from` to `to` (minutes after midnight; across midnight when
/// `to` is earlier), all Saturday and Sunday when `weekends`, and whenever "Quiet for 1 hour" is running.
public struct QuietHours: Equatable, Sendable {
    public var on: Bool
    public var from: Int
    public var to: Int
    public var weekends: Bool

    public init(on: Bool, from: Int, to: Int, weekends: Bool) {
        self.on = on; self.from = from; self.to = to; self.weekends = weekends
    }

    /// Off at first; 7 PM to 8 AM when turned on.
    public static let standard = QuietHours(on: false, from: 19 * 60, to: 8 * 60, weekends: false)

    /// Quiet at `date` by the schedule, or because of "Quiet for 1 hour" (`quietUntil`).
    public func isQuiet(at date: Date, calendar: Calendar, quietUntil: Date? = nil) -> Bool {
        if let quietUntil, date < quietUntil { return true }
        guard on else { return false }
        if weekends, calendar.isDateInWeekend(date) { return true }
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        if from == to { return false }
        return from < to ? (minute >= from && minute < to) : (minute >= from || minute < to)
    }

    /// When the quiet that's on at `date` ends (the first minute that isn't quiet), or nil when it isn't quiet.
    public func quietEnds(at date: Date, calendar: Calendar, quietUntil: Date? = nil) -> Date? {
        guard isQuiet(at: date, calendar: calendar, quietUntil: quietUntil) else { return nil }
        // Minute by minute from the next whole minute, up to 8 days (a weekend plus the nights around it).
        let start = calendar.dateInterval(of: .minute, for: date)?.end ?? date
        for step in 0..<(8 * 24 * 60) {
            let t = start.addingTimeInterval(TimeInterval(step * 60))
            if !isQuiet(at: t, calendar: calendar, quietUntil: quietUntil) { return t }
        }
        return nil
    }

    /// "19:00" for 19 × 60; parsing the same.
    public static func clock(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }
    static func minutes(_ clock: String) -> Int? {
        let p = clock.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2, (0..<24).contains(p[0]), (0..<60).contains(p[1]) else { return nil }
        return p[0] * 60 + p[1]
    }
}

/// The keyboard shortcut that opens ClaudeBar: a key with at least Control, Option or Command. Stored as
/// "ctrl+opt+C", shown as "⌃⌥C"; `keyCode` is the Carbon virtual key code.
public struct Shortcut: Equatable, Sendable {
    public var keyCode: UInt32
    public var key: String
    public var control: Bool
    public var option: Bool
    public var shift: Bool
    public var command: Bool

    public static let standard = Shortcut(string: "ctrl+opt+C")!

    /// Carbon virtual key codes (ANSI layout) of the keys a shortcut may use.
    static let keys: [String: UInt32] = [
        "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7, "C": 8, "V": 9, "B": 11, "Q": 12, "W": 13, "E": 14,
        "R": 15, "Y": 16, "T": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
        "O": 31, "U": 32, "I": 34, "P": 35, "L": 37, "J": 38, "K": 40, "N": 45, "M": 46, "Space": 49,
        "F1": 122, "F2": 120, "F3": 99, "F4": 118, "F5": 96, "F6": 97, "F7": 98, "F8": 100, "F9": 101, "F10": 109,
        "F11": 103, "F12": 111,
    ]

    public init?(string: String) {
        var control = false, option = false, shift = false, command = false, key: String?
        for part in string.split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch part.lowercased() {
            case "ctrl", "control": control = true
            case "opt", "option", "alt": option = true
            case "shift": shift = true
            case "cmd", "command": command = true
            default: key = Self.keys.keys.first { $0.lowercased() == part.lowercased() }; if key == nil { return nil }
            }
        }
        guard let key, let code = Self.keys[key], control || option || command else { return nil }
        self.init(keyCode: code, key: key, control: control, option: option, shift: shift, command: command)
    }

    /// From a key press (Carbon key code and the modifiers held); nil for a key that can't be a shortcut.
    public init?(keyCode: UInt32, control: Bool, option: Bool, shift: Bool, command: Bool) {
        guard let key = Self.keys.first(where: { $0.value == keyCode })?.key, control || option || command else { return nil }
        self.init(keyCode: keyCode, key: key, control: control, option: option, shift: shift, command: command)
    }

    private init(keyCode: UInt32, key: String, control: Bool, option: Bool, shift: Bool, command: Bool) {
        self.keyCode = keyCode; self.key = key
        self.control = control; self.option = option; self.shift = shift; self.command = command
    }

    /// "⌃⌥⇧⌘C", in macOS's order.
    public var display: String {
        (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + key
    }

    /// "ctrl+opt+shift+cmd+C", as the settings file keeps it.
    public var string: String {
        ([control ? "ctrl" : nil, option ? "opt" : nil, shift ? "shift" : nil, command ? "cmd" : nil, key] as [String?])
            .compactMap { $0 }.joined(separator: "+")
    }
}
