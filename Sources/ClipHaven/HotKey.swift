import Carbon.HIToolbox

/// A system-wide hotkey through Carbon's `RegisterEventHotKey`, which needs no Accessibility
/// permission. Codes and modifiers are Carbon's, as ClipMenu stores them (V is 9, Cmd+Ctrl is 4352).
@MainActor
final class HotKey {
    static let defaultKeyCode = UInt32(kVK_ANSI_V)
    static let defaultModifiers = UInt32(cmdKey | controlKey)

    let keyCode: UInt32
    let modifiers: UInt32
    fileprivate let action: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Nil when the combination cannot be registered.
    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.action = action

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard InstallEventHandler(GetApplicationEventTarget(), hotKeyPressed, 1, &spec, me, &handlerRef) == noErr else { return nil }

        let id = EventHotKeyID(signature: OSType(0x4348_4856), id: 1) // "CHHV"
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr else {
            NSLog("ClipHaven: hotkey \(keyCode)/\(modifiers) not registered: \(status)")
            RemoveEventHandler(handlerRef)
            return nil
        }
    }

    isolated deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    /// The combination as the menu shows it, e.g. "⌃⌘V".
    var displayName: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + (keyCode == UInt32(kVK_ANSI_V) ? "V" : "key \(keyCode)")
    }
}

/// Carbon delivers hotkey events on the main thread.
private func hotKeyPressed(_: EventHandlerCallRef?, _: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let address = UInt(bitPattern: userData) // a plain value can cross into the main actor
    MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
        Unmanaged<HotKey>.fromOpaque(pointer).takeUnretainedValue().action()
    }
    return noErr
}
