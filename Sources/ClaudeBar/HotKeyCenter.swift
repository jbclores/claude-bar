import Carbon
import ClaudeBarCore
import Foundation

/// Which global shortcut: the one that opens ClaudeBar, or the one held to talk.
enum HotKeySlot: UInt32 {
    case open = 1, talk = 2
}

/// ClaudeBar's global shortcuts (Carbon hot keys: no Accessibility permission needed), one per slot.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    /// Called on the main thread when a slot's shortcut is pressed.
    var onPress: [HotKeySlot: () -> Void] = [:]
    /// Called on the main thread when a slot's shortcut is let go.
    var onRelease: [HotKeySlot: () -> Void] = [:]
    private var refs: [HotKeySlot: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?

    /// Registers `shortcut` for `slot` in place of the last one (nil: none). False when another app already has it.
    @discardableResult
    func register(_ shortcut: Shortcut?, slot: HotKeySlot) -> Bool {
        installHandler()
        if let ref = refs.removeValue(forKey: slot) { UnregisterEventHotKey(ref) }
        guard let shortcut else { return true }
        var mods: UInt32 = 0
        if shortcut.control { mods |= UInt32(controlKey) }
        if shortcut.option { mods |= UInt32(optionKey) }
        if shortcut.shift { mods |= UInt32(shiftKey) }
        if shortcut.command { mods |= UInt32(cmdKey) }
        let id = EventHotKeyID(signature: OSType(0x4342_6172), id: slot.rawValue) // "CBar"
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, mods, id, GetApplicationEventTarget(), 0, &newRef)
        guard status == noErr, let newRef else { return false }
        refs[slot] = newRef
        return true
    }

    private func installHandler() {
        guard handler == nil else { return }
        var specs = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, let slot = HotKeySlot(rawValue: id.id) else { return OSStatus(eventNotHandledErr) }
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let center = HotKeyCenter.shared
                    (pressed ? center.onPress[slot] : center.onRelease[slot])?()
                }
            }
            return noErr
        }, specs.count, &specs, nil, &handler)
    }
}
