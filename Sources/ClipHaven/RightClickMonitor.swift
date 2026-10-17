import AppKit
@preconcurrency import ApplicationServices
@preconcurrency import CoreGraphics
import ClipHavenCore

/// Opens ClipHaven's menu on a right-click made with the recorded modifier keys (Control for the
/// action menu and Shift+Control for the paste menu, unless changed in Preferences). A plain
/// right-click is left to the app.
///
/// A session event tap sees each right-mouse press. If the element under the pointer is an editable
/// text field (asked through Accessibility, with a short timeout so a slow app is simply left
/// alone), the press and its release are swallowed, so the app's own context menu does not open,
/// and `onRightClick` runs. Every other right-click passes through untouched. Needs Accessibility,
/// which auto-paste already needs.
@MainActor
final class RightClickMonitor {
    /// The click point and whether the menu opens in action mode (Control without Shift).
    var onRightClick: (CGPoint, Bool) -> Void = { _, _ in }
    /// The recorded gestures, read at every click so a change in Preferences applies at once.
    var gestures: () -> (paste: RightClickModifiers, actions: RightClickModifiers) = {
        (RightClickGesture.defaultPaste, RightClickGesture.defaultActions)
    }
    /// Set while Preferences is recording a gesture, so that right-click reaches the recorder.
    var isPaused = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var swallowingRelease = false

    var isRunning: Bool { tap != nil }

    /// Starts the tap. False when macOS refuses it, which means Accessibility is not granted.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        guard AXIsProcessTrusted() else { return false }
        let mask = CGEventMask(1 << CGEventType.rightMouseDown.rawValue) | CGEventMask(1 << CGEventType.rightMouseUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<RightClickMonitor>.fromOpaque(refcon).takeUnretainedValue()
            return MainActor.assumeIsolated { monitor.handle(type, event) }
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        tap = nil
        source = nil
        swallowingRelease = false
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        case .rightMouseDown:
            guard !isPaused else { return Unmanaged.passUnretained(event) }
            let chosen = gestures()
            guard let mode = RightClickGesture.mode(for: Self.modifiers(event.flags), paste: chosen.paste, actions: chosen.actions)
            else { return Unmanaged.passUnretained(event) }
            let point = event.location
            let target = Self.element(at: point)
            // ClipHaven's own menus and windows keep their right-clicks (the actions on a menu item).
            if let target, target.pid == ProcessInfo.processInfo.processIdentifier { return Unmanaged.passUnretained(event) }
            // The keys were held on purpose, so this opens whether or not the app shows a text field
            // to Accessibility (Terminal and some browsers do not). A field is only needed to focus it.
            let field = target.flatMap { Self.isEditable($0.element) ? $0.element : nil }
            swallowingRelease = true
            DispatchQueue.main.async { [weak self] in self?.open(at: point, field: field, actions: mode == .actions) }
            return nil
        case .rightMouseUp:
            guard swallowingRelease else { return Unmanaged.passUnretained(event) }
            swallowingRelease = false
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// Puts the caret in the field if it is not already focused (a right-click normally does), then
    /// shows the menu, so the paste goes where the click was.
    private func open(at point: CGPoint, field: AXUIElement?, actions: Bool) {
        var focused: CFTypeRef?
        if let field { AXUIElementCopyAttributeValue(field, kAXFocusedAttribute as CFString, &focused) }
        if field != nil, (focused as? Bool) != true {
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
                    .post(tap: .cghidEventTap)
            }
            // Let the click land before the menu takes the pointer.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in self?.onRightClick(point, actions) }
        } else {
            onRightClick(point, actions)
        }
    }

    private static func modifiers(_ flags: CGEventFlags) -> RightClickModifiers {
        var held: RightClickModifiers = []
        if flags.contains(.maskShift) { held.insert(.shift) }
        if flags.contains(.maskControl) { held.insert(.control) }
        if flags.contains(.maskAlternate) { held.insert(.option) }
        if flags.contains(.maskCommand) { held.insert(.command) }
        return held
    }

    /// The Accessibility element under `point` (screen coordinates, top-left origin) and its app.
    private static func element(at point: CGPoint) -> (element: AXUIElement, pid: pid_t)? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)
        var found: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &found) == .success, let element = found else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return (element, pid)
    }

    private static func isEditable(_ element: AXUIElement) -> Bool {
        func string(_ attribute: String) -> String? {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value as? String : nil
        }
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        return EditableField.isEditable(role: string(kAXRoleAttribute), subrole: string(kAXSubroleAttribute),
                                        valueIsSettable: settable.boolValue)
    }
}
