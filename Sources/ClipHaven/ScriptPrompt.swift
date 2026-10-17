import AppKit

/// The question box behind a script's `prompt()`.
@MainActor
enum ScriptPrompt {
    /// The text the owner typed, or nil if they cancelled.
    static func ask(_ question: String) -> String? {
        let alert = NSAlert()
        alert.messageText = question
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }
}
