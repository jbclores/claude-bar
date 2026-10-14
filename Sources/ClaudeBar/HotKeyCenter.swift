import Carbon
import ClaudeBarCore
import Foundation

/// The global shortcut that opens ClaudeBar (Carbon hot keys: no Accessibility permission needed).
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    /// Called on the main thread when the shortcut is pressed.
    var onPress: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?

    /// Registers `shortcut` in place of the last one (nil: none). False when another app already has it.
    @discardableResult
    func register(_ shortcut: Shortcut?) -> Bool {
        installHandler()
        if let ref { UnregisterEventHotKey(ref); self.ref = nil }
        guard let shortcut else { return true }
        var mods: UInt32 = 0
        if shortcut.control { mods |= UInt32(controlKey) }
        if shortcut.option { mods |= UInt32(optionKey) }
        if shortcut.shift { mods |= UInt32(shiftKey) }
        if shortcut.command { mods |= UInt32(cmdKey) }
        let id = EventHotKeyID(signature: OSType(0x4342_6172), id: 1) // "CBar"
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, mods, id, GetApplicationEventTarget(), 0, &newRef)
        guard status == noErr else { return false }
        ref = newRef
        return true
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { HotKeyCenter.shared.onPress?() } }
            return noErr
        }, 1, &spec, nil, &handler)
    }
}
