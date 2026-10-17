import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ClipHavenCore

/// Pastes into the frontmost app with a synthesised Cmd+V, as ClipMenu's `postCommandV()` does.
/// Posting keyboard events needs Accessibility; until it is granted the clip stays on the
/// clipboard and the owner pastes by hand.
final class KeyPoster: PasteKeyPoster {
    /// Lets the menu close and focus return to the app being pasted into.
    static let delay: TimeInterval = 0.05

    func postPaste() {
        guard Self.isTrusted(prompt: true) else {
            NSLog("ClipHaven: Accessibility not granted; clip left on the clipboard")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.delay) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let v = CGKeyCode(kVK_ANSI_V)
            for keyDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: keyDown)
                event?.flags = .maskCommand
                event?.post(tap: .cgSessionEventTap)
            }
        }
    }

    /// Whether this build may post events; with `prompt`, macOS shows its Accessibility dialog.
    static func isTrusted(prompt: Bool) -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": prompt] as CFDictionary)
    }
}
