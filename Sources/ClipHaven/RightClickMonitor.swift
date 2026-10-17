import AppKit
@preconcurrency import ApplicationServices
@preconcurrency import CoreGraphics
import ClipHavenCore

/// Opens ClipHaven's menu when you right-click a field you can paste into.
///
/// A session event tap sees each right-mouse press. If the element under the pointer is an editable
/// text field (asked through Accessibility, with a short timeout so a slow app is simply left
/// alone), the press and its release are swallowed, so the app's own context menu does not open,
/// and `onRightClick` runs. Every other right-click passes through untouched. Needs Accessibility,
/// which auto-paste already needs.
@MainActor
final class RightClickMonitor {
    var onRightClick: (CGPoint) -> Void = { _ in }
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
            let point = event.location
            guard let field = Self.editableField(at: point) else { return Unmanaged.passUnretained(event) }
            swallowingRelease = true
            DispatchQueue.main.async { [weak self] in self?.open(at: point, field: field) }
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
    private func open(at point: CGPoint, field: AXUIElement) {
        var focused: CFTypeRef?
        AXUIElementCopyAttributeValue(field, kAXFocusedAttribute as CFString, &focused)
        if (focused as? Bool) != true {
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
                    .post(tap: .cghidEventTap)
            }
            // Let the click land before the menu takes the pointer.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in self?.onRightClick(point) }
        } else {
            onRightClick(point)
        }
    }

    /// The editable text field under `point` (screen coordinates, top-left origin), or nil.
    private static func editableField(at point: CGPoint) -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)
        var found: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &found) == .success, let element = found else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard pid != ProcessInfo.processInfo.processIdentifier else { return nil } // our own menus and windows

        func string(_ attribute: String) -> String? {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value as? String : nil
        }
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        guard EditableField.isEditable(role: string(kAXRoleAttribute), subrole: string(kAXSubroleAttribute),
                                       valueIsSettable: settable.boolValue) else { return nil }
        return element
    }
}
