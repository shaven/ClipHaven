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
    private var paster: Paster?
    private var secretPaster: SecretPaster?
    private var preferencesWindow: PreferencesWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        applyStatusIcon()

        do {
            let prefs = Preferences()
            let store = try HistoryStore(url: try Self.historyURL(), limits: prefs.limits)
            self.store = store
            let pasteboard = SystemPasteboard()
            monitor = ClipboardMonitor(source: pasteboard, store: store)
            // ClipMenu's `inputPasteCommand`: paste straight into the frontmost app.
            let paster = Paster(store: store, writer: pasteboard, poster: KeyPoster(), autoPaste: prefs.autoPaste)
            self.paster = paster
            let snippets = try SnippetStore(url: store.url)
            let authenticator = TouchIDAuthenticator()
            let secretPaster = SecretPaster(snippets: snippets, secrets: KeychainProvider(authenticator: authenticator),
                                            authenticator: authenticator, pasteboard: pasteboard, poster: KeyPoster(),
                                            scheduler: MainScheduler(),
                                            autoPaste: prefs.autoPaste, restoreDelay: prefs.restoreDelay)
            self.secretPaster = secretPaster
            let support = try Self.supportDirectory()
            let scripts = support.appendingPathComponent("script", isDirectory: true)
            let bundledScripts = Bundle.main.resourceURL?.appendingPathComponent("script") ?? scripts
            let actionFolders = [scripts.appendingPathComponent("action"), bundledScripts.appendingPathComponent("action")]
            let runner = ScriptRunner(
                libFolders: [scripts.appendingPathComponent("lib"), bundledScripts.appendingPathComponent("lib")],
                prompt: { question in DispatchQueue.main.sync { MainActor.assumeIsolated { ScriptPrompt.ask(question) } } },
                activate: { DispatchQueue.main.sync { MainActor.assumeIsolated { NSApp.activate() } } })
            let actionStore = ActionStore(url: support.appendingPathComponent("actions.json"))
            Self.importClipMenuActionsOnce(into: actionStore, backups: support.appendingPathComponent("backups", isDirectory: true))
            let actions = ActionService(paster: paster, store: store, runner: runner, actionFolders: actionFolders)
            let controller = MenuController(store: store, snippets: snippets, paster: paster, secretPaster: secretPaster,
                                            actions: actions, actionStore: actionStore, scriptsFolder: scripts, actionFolders: actionFolders,
                                            syncStore: SyncSnapshotStore())
            menuController = controller
            controller.layout = prefs.layout
            controller.appearance = prefs.appearance
            controller.showPreferences = { [weak self] in self?.showPreferences() }
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

    /// A menu-bar-only app has no menu bar of its own, so Cmd+C, Cmd+V, Cmd+Z and the rest reach
    /// no text field. This menu is never drawn; it only routes those key equivalents.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit ClipHaven", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = main
    }

    /// Cmd+Ctrl+V, ClipMenu's combination. While ClipMenu is still running it owns that, so
    /// ClipHaven takes Cmd+Ctrl+Option+V until cutover. `hotKeyCode` / `hotKeyModifiers`
    /// (Carbon values) override both.
    private func registerHotKey() {
        let prefs = Preferences()
        hotKey = nil // release the old combination before taking the new one
        let clipMenuRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.naotaka.ClipMenu").isEmpty
        var modifiers = prefs.hotKeyModifiers
        if clipMenuRunning, !prefs.hasCustomHotKey { modifiers |= UInt32(optionKey) }
        let keyCode = prefs.hotKeyCode

        hotKey = HotKey(keyCode: keyCode, modifiers: modifiers) { [weak self] in
            self?.menuController?.popUpAtCursor()
        }
        menuController?.hotKeyNote = hotKey.map { "Hotkey: \($0.displayName)" } ?? "Hotkey unavailable"
    }

    private func showPreferences() {
        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindow { [weak self] in self?.applyPreferences() }
        }
        preferencesWindow?.show()
    }

    /// ClipHaven's drawn icon, or one of ClipMenu's PNGs. Coloured ones are shown as they are;
    /// the black ones are tinted by macOS for light and dark menu bars.
    private func applyStatusIcon() {
        let choice = StatusIconChoice.resolve(Preferences().statusIcon)
        guard let file = choice.file,
              let url = Bundle.main.resourceURL?.appendingPathComponent("StatusIcons/\(file)"),
              let image = NSImage(contentsOf: url) else {
            statusItem?.button?.image = StatusIcon.make()
            return
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = !choice.isColour
        image.accessibilityDescription = "ClipHaven"
        statusItem?.button?.image = image
    }

    /// Pushes the saved settings into the running app. The history size is read at launch.
    private func applyPreferences() {
        let prefs = Preferences()
        paster?.autoPaste = prefs.autoPaste
        secretPaster?.autoPaste = prefs.autoPaste
        secretPaster?.restoreDelay = prefs.restoreDelay
        menuController?.layout = prefs.layout
        menuController?.appearance = prefs.appearance
        applyStatusIcon()
        registerHotKey()
    }

    /// `~/Library/Application Support/ClipHaven`
    private static func supportDirectory() throws -> URL {
        let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("ClipHaven", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// `~/Library/Application Support/ClipHaven/history.sqlite`
    private static func historyURL() throws -> URL {
        try supportDirectory().appendingPathComponent("history.sqlite")
    }

    /// On the first run with no saved list, takes over ClipMenu's `actions.plist` if there is one.
    /// Later runs leave the saved list alone; "Import ClipMenu Actions…" replaces it on request.
    private static func importClipMenuActionsOnce(into store: ActionStore, backups: URL) {
        guard (try? store.load()) == nil else { return }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let source = support.appendingPathComponent("ClipMenu/actions.plist")
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        do {
            try store.save(try ActionList.importFile(at: source, backupDirectory: backups).tree)
        } catch {
            NSLog("ClipHaven: ClipMenu actions not imported: \(error)")
        }
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

HistoryImportMode.runIfRequested()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
