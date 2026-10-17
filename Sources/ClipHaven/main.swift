import AppKit
import Carbon.HIToolbox
import ClipHavenCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var store: HistoryStore?
    private var monitor: ClipboardMonitor?
    private var pollTimer: Timer?
    private var menuController: MenuController?
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = StatusIcon.make()
        statusItem = item

        do {
            let store = try HistoryStore(url: try Self.historyURL())
            self.store = store
            let pasteboard = SystemPasteboard()
            monitor = ClipboardMonitor(source: pasteboard, store: store)
            // ClipMenu's `inputPasteCommand`: paste straight into the frontmost app.
            UserDefaults.standard.register(defaults: ["autoPaste": true])
            let paster = Paster(store: store, writer: pasteboard, poster: KeyPoster(),
                                autoPaste: UserDefaults.standard.bool(forKey: "autoPaste"))
            let controller = MenuController(store: store, paster: paster)
            menuController = controller
            registerHotKey()
            item.menu = controller.makeStatusMenu()
            startPolling()
        } catch {
            NSLog("ClipHaven: history unavailable: \(error)")
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "History unavailable", action: nil, keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Quit ClipHaven", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            item.menu = menu
        }
    }

    /// Cmd+Ctrl+V, ClipMenu's combination. While ClipMenu is still running it owns that, so
    /// ClipHaven takes Cmd+Ctrl+Option+V until cutover. `hotKeyCode` / `hotKeyModifiers`
    /// (Carbon values) override both.
    private func registerHotKey() {
        let defaults = UserDefaults.standard
        let clipMenuRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.naotaka.ClipMenu").isEmpty
        var modifiers = HotKey.defaultModifiers
        if clipMenuRunning { modifiers |= UInt32(optionKey) }
        let keyCode = (defaults.object(forKey: "hotKeyCode") as? Int).map(UInt32.init) ?? HotKey.defaultKeyCode
        modifiers = (defaults.object(forKey: "hotKeyModifiers") as? Int).map(UInt32.init) ?? modifiers

        hotKey = HotKey(keyCode: keyCode, modifiers: modifiers) { [weak self] in
            self?.menuController?.popUpAtCursor()
        }
        menuController?.hotKeyNote = hotKey.map { "Hotkey: \($0.displayName)" } ?? "Hotkey unavailable"
    }

    /// `~/Library/Application Support/ClipHaven/history.sqlite`
    private static func historyURL() throws -> URL {
        let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("ClipHaven", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.sqlite")
    }

    /// Checks the pasteboard twice a second; the tolerance lets macOS coalesce wake-ups.
    private func startPolling() {
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func poll() {
        do {
            try monitor?.poll()
        } catch {
            NSLog("ClipHaven: capture failed: \(error)")
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
