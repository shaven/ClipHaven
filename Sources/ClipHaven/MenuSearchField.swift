import AppKit
import ClipHavenCore

/// The filter field at the top of the menu. Typing reports each change; Return reports a request
/// to choose the first match.
@MainActor
final class MenuSearchField: NSView, NSSearchFieldDelegate {
    private let field = NSSearchField()
    private let scopeControl = NSSegmentedControl(labels: ["All", "Name", "Text"], trackingMode: .selectOne, target: nil, action: nil)
    var onChange: (String) -> Void = { _ in }
    /// The switch beside the field; reports the new scope, and the caller searches again.
    var onScope: (SearchScope) -> Void = { _ in }
    var text: String { field.stringValue }
    var scope: SearchScope {
        get { SearchScope(rawValue: scopeControl.selectedSegment) ?? .all }
        set { scopeControl.selectedSegment = newValue.rawValue }
    }
    var onReturn: () -> Void = {}

    override init(frame: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 330, height: 32))
        field.frame = NSRect(x: 10, y: 5, width: 175, height: 22)
        scopeControl.controlSize = .small
        scopeControl.font = .systemFont(ofSize: 11)
        scopeControl.segmentStyle = .rounded
        scopeControl.frame = NSRect(x: 192, y: 5, width: 128, height: 22)
        scopeControl.toolTip = "All: titles and text. Name: titles and folder names only. Text: the contents only."
        scopeControl.target = self
        scopeControl.action = #selector(scopeChanged)
        scopeControl.selectedSegment = 0
        addSubview(scopeControl)
        field.placeholderString = "Filter clips and snippets"
        field.delegate = self
        addSubview(field)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        // The menu window only exists once the menu is up; focus the field on the next turn.
        DispatchQueue.main.async { [field] in window.makeFirstResponder(field) }
    }

    @objc private func scopeChanged() {
        onScope(scope)
        window?.makeFirstResponder(field)
    }

    func controlTextDidChange(_ notification: Notification) {
        onChange(field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
        onReturn()
        return true
    }
}

/// Reports which item a menu is about to highlight; set as the delegate of every submenu, which
/// would otherwise not tell anyone.
@MainActor
final class HighlightWatcher: NSObject, NSMenuDelegate {
    var onHighlight: (NSMenuItem?) -> Void = { _ in }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        onHighlight(item)
    }
}
