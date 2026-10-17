import AppKit
import ClipHavenCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var store: HistoryStore?
    private var monitor: ClipboardMonitor?
    private var pollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = StatusIcon.make()
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "ClipHaven \(ClipHaven.version)", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit ClipHaven", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item

        do {
            let store = try HistoryStore(url: try Self.historyURL())
            self.store = store
            monitor = ClipboardMonitor(source: SystemPasteboard(), store: store)
            startPolling()
        } catch {
            NSLog("ClipHaven: history unavailable: \(error)")
        }
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
