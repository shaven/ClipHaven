import AppKit

/// Notices a Control-click, an Option-click or a right-click (a two-finger click) on a menu item.
///
/// macOS runs a menu item's action a moment after the menu closes, by when the Control key or the
/// right button has usually been let go, and a Control-click arrives as a right-click without its
/// modifier. So while a menu is open the keys and buttons held right now are sampled, and a press
/// seen in the last half second counts.
@MainActor
final class ActionClickTracker {
    private var timer: Timer?
    private var lastSeen = Date.distantPast
    private var stopWork: DispatchWorkItem?

    var sawActionClick: Bool { Date().timeIntervalSince(lastSeen) < 0.5 }

    func start() {
        stopWork?.cancel()
        reset()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        RunLoop.main.add(timer, forMode: .common) // .common includes the menu's tracking mode
        self.timer = timer
    }

    func stop(after delay: TimeInterval) {
        stopWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.timer?.invalidate()
                self?.timer = nil
            }
        }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func reset() {
        lastSeen = .distantPast
    }

    private func sample() {
        // Bit 1 of the mouse button mask is the right button. Option works too, as a plain key.
        let keys = NSEvent.modifierFlags
        if keys.contains(.control) || keys.contains(.option) || NSEvent.pressedMouseButtons & 0b10 != 0 {
            lastSeen = Date()
        }
    }
}
