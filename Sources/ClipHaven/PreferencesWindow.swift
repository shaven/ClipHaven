import AppKit
import Carbon.HIToolbox
import ClipHavenCore

/// The settings window. Every change is written at once and handed to `onChange`, which applies
/// it to the running app. The history size is read at launch, so it says so.
@MainActor
final class PreferencesWindow: NSObject, NSWindowDelegate {
    private var prefs = Preferences()
    private let onChange: () -> Void
    private var window: NSWindow?
    private var recorder: Any?
    private let hotKeyLabel = NSTextField(labelWithString: "")
    private let hotKeyButton = NSButton(title: "Record…", target: nil, action: nil)
    private let loginNote = NSTextField(labelWithString: "")
    private var controls: [String: NSControl] = [:]

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func show() {
        if window == nil { build() }
        refresh()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Window

    private func build() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 470),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "ClipHaven Preferences"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        hotKeyButton.target = self
        hotKeyButton.action = #selector(recordHotKey)
        let defaultButton = NSButton(title: "Default", target: self, action: #selector(defaultHotKey))
        let hotKeyRow = NSStackView(views: [hotKeyLabel, hotKeyButton, defaultButton])
        hotKeyRow.spacing = 8

        loginNote.textColor = .secondaryLabelColor
        loginNote.font = .systemFont(ofSize: 11)
        let reset = NSButton(title: "Restore Defaults", target: self, action: #selector(restoreDefaults))

        let grid = NSGridView(views: [
            [label("Hotkey"), hotKeyRow],
            [label(""), check("autoPaste", "Paste into the frontmost app when a clip is chosen")],
            [label(""), check("numbered", "Number the menu items")],
            [label("Clips in the menu"), number("inlineCount")],
            [label("Clips per folder"), number("folderSize")],
            [label("Title length"), number("titleLength")],
            [label("History size"), number("maxCount"), ],
            [label(""), note("Read at launch: quit and reopen ClipHaven after changing it.")],
            [label("Menu icons"), check("showIcons", "Show icons in the menu")],
            [label(""), check("showThumbnails", "Show thumbnails for images")],
            [label("Icon size"), popup("iconSize", Self.iconSizes.map { "\($0) pt" })],
            [label("Status bar icon"), popup("statusIcon", StatusIconChoice.all.map(\.title))],
            [label("Restore clipboard after"), number("restoreDelay", suffix: "seconds")],
            [label(""), check("login", "Start ClipHaven at login")],
            [label(""), loginNote],
            [label(""), reset],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])
        window.contentView = content
        self.window = window
    }

    private func label(_ text: String) -> NSTextField { NSTextField(labelWithString: text) }

    private func note(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.textColor = .secondaryLabelColor
        field.font = .systemFont(ofSize: 11)
        return field
    }

    private func check(_ id: String, _ title: String) -> NSButton {
        let box = NSButton(checkboxWithTitle: title, target: self, action: #selector(changed(_:)))
        box.identifier = .init(id)
        controls[id] = box
        return box
    }

    private func number(_ id: String, suffix: String? = nil) -> NSView {
        let field = NSTextField()
        field.identifier = .init(id)
        field.alignment = .right
        field.target = self
        field.action = #selector(changed(_:))
        field.widthAnchor.constraint(equalToConstant: 70).isActive = true
        controls[id] = field
        guard let suffix else { return field }
        let row = NSStackView(views: [field, label(suffix)])
        row.spacing = 6
        return row
    }

    private static let iconSizes = [16, 32, 48]

    private func popup(_ id: String, _ titles: [String]) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.addItems(withTitles: titles)
        button.identifier = .init(id)
        button.target = self
        button.action = #selector(changed(_:))
        controls[id] = button
        return button
    }

    func windowWillClose(_ notification: Notification) {
        stopRecording()
    }

    // MARK: - Values

    private func refresh() {
        (controls["autoPaste"] as? NSButton)?.state = prefs.autoPaste ? .on : .off
        (controls["numbered"] as? NSButton)?.state = prefs.numbered ? .on : .off
        (controls["login"] as? NSButton)?.state = LoginItem.isEnabled ? .on : .off
        (controls["showIcons"] as? NSButton)?.state = prefs.showIcons ? .on : .off
        (controls["showThumbnails"] as? NSButton)?.state = prefs.showThumbnails ? .on : .off
        (controls["iconSize"] as? NSPopUpButton)?.selectItem(at: Self.iconSizes.firstIndex(of: prefs.iconSize) ?? 0)
        (controls["statusIcon"] as? NSPopUpButton)?.selectItem(at: StatusIconChoice.all.firstIndex { $0.id == prefs.statusIcon } ?? 0)
        controls["inlineCount"]?.integerValue = prefs.inlineCount
        controls["folderSize"]?.integerValue = prefs.folderSize
        controls["titleLength"]?.integerValue = prefs.titleLength
        controls["maxCount"]?.integerValue = prefs.maxCount
        controls["restoreDelay"]?.doubleValue = prefs.restoreDelay
        hotKeyLabel.stringValue = Self.describe(code: prefs.hotKeyCode, modifiers: prefs.hotKeyModifiers)
        loginNote.stringValue = LoginItem.note
    }

    @objc private func changed(_ sender: NSControl) {
        switch sender.identifier?.rawValue {
        case "autoPaste": prefs.autoPaste = sender.integerValue != 0
        case "numbered": prefs.numbered = sender.integerValue != 0
        case "inlineCount": prefs.inlineCount = sender.integerValue
        case "folderSize": prefs.folderSize = sender.integerValue
        case "titleLength": prefs.titleLength = sender.integerValue
        case "maxCount": prefs.maxCount = sender.integerValue
        case "restoreDelay": prefs.restoreDelay = sender.doubleValue
        case "showIcons": prefs.showIcons = sender.integerValue != 0
        case "showThumbnails": prefs.showThumbnails = sender.integerValue != 0
        case "iconSize":
            if let index = (sender as? NSPopUpButton)?.indexOfSelectedItem { prefs.iconSize = Self.iconSizes[index] }
        case "statusIcon":
            if let index = (sender as? NSPopUpButton)?.indexOfSelectedItem { prefs.statusIcon = StatusIconChoice.all[index].id }
        case "login":
            do { try LoginItem.set(sender.integerValue != 0) } catch { NSLog("ClipHaven: login item: \(error)") }
        default: break
        }
        refresh()
        onChange()
    }

    @objc private func restoreDefaults() {
        prefs.reset()
        refresh()
        onChange()
    }

    // MARK: - Hotkey

    @objc private func recordHotKey() {
        stopRecording()
        hotKeyLabel.stringValue = "Press the new combination…"
        recorder = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.finishRecording(event) }
            return nil
        }
    }

    private func finishRecording(_ event: NSEvent) {
        let modifiers = Self.carbonModifiers(event.modifierFlags)
        // A bare key would hijack typing; require Cmd, Ctrl or Option.
        guard modifiers & UInt32(cmdKey | controlKey | optionKey) != 0 else { NSSound.beep(); return }
        stopRecording()
        prefs.hotKeyCode = UInt32(event.keyCode)
        prefs.hotKeyModifiers = modifiers
        refresh()
        onChange()
    }

    @objc private func defaultHotKey() {
        stopRecording()
        prefs.hotKeyCode = Preferences.defaultHotKeyCode
        prefs.hotKeyModifiers = Preferences.defaultHotKeyModifiers
        refresh()
        onChange()
    }

    private func stopRecording() {
        if let recorder { NSEvent.removeMonitor(recorder) }
        recorder = nil
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    private static func describe(code: UInt32, modifiers: UInt32) -> String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + (code == UInt32(kVK_ANSI_V) ? "V" : "key \(code)")
    }
}
