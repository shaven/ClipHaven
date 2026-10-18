import AppKit
import ClipHavenCore

/// The action-list editor: the Control-click menu as a tree you can reorder, rename, nest and
/// add to. Every edit is saved at once.
@MainActor
final class ActionEditor: NSObject, NSWindowDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate {
    private final class Entry {
        let path: [Int]
        let node: ActionNode
        let children: [Entry]

        init(path: [Int], node: ActionNode) {
            self.path = path
            self.node = node
            if case .folder(let kids) = node.kind {
                children = kids.enumerated().map { Entry(path: path + [$0.offset], node: $0.element) }
            } else {
                children = []
            }
        }
    }

    private let load: () -> [ActionNode]
    private let save: ([ActionNode]) -> Void
    private let scripts: () -> [ActionNode]
    private let defaults: () -> [ActionNode]
    private var tree: [ActionNode] = []
    private var roots: [Entry] = []

    private var window: NSWindow?
    private let outline = NSOutlineView()
    private let addScriptButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let addBuiltinButton = NSPopUpButton(frame: .zero, pullsDown: true)

    init(load: @escaping () -> [ActionNode], save: @escaping ([ActionNode]) -> Void,
         scripts: @escaping () -> [ActionNode], defaults: @escaping () -> [ActionNode]) {
        self.load = load
        self.save = save
        self.scripts = scripts
        self.defaults = defaults
    }

    func show() {
        if window == nil { build() }
        tree = load()
        reload()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    // MARK: - Window

    private func build() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "ClipHaven Actions"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        column.title = "Action menu (double-click a name to rename it)"
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.dataSource = self
        outline.delegate = self
        outline.allowsMultipleSelection = false
        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        addScriptButton.addItem(withTitle: "Add Script")
        addBuiltinButton.addItem(withTitle: "Add Built-in")

        let row1 = NSStackView(views: [addScriptButton, addBuiltinButton, button("Add Folder", #selector(addFolder)),
                                       button("Remove", #selector(removeSelected))])
        let row2 = NSStackView(views: [button("Move Up", #selector(moveUp)), button("Move Down", #selector(moveDown)),
                                       button("Into Folder Above", #selector(indent)), button("Out of Folder", #selector(outdent)),
                                       button("Reset to Default…", #selector(reset))])
        for row in [row1, row2] { row.spacing = 8 }
        let note = NSTextField(wrappingLabelWithString:
            "Scripts you add to the scripts folder appear under My Scripts until you place them here. A built-in or script only shows for clips it applies to.")
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 11)

        let stack = NSStackView(views: [scroll, row1, row2, note])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        let content = window.contentView!
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            note.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        self.window = window
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        NSButton(title: title, target: self, action: action)
    }

    // MARK: - Data

    private func reload(select path: [Int]? = nil) {
        roots = tree.enumerated().map { Entry(path: [$0.offset], node: $0.element) }
        outline.reloadData()
        outline.expandItem(nil, expandChildren: true)
        if let path, let entry = entry(at: path) {
            let row = outline.row(forItem: entry)
            if row >= 0 { outline.selectRowIndexes([row], byExtendingSelection: false) }
        }
        fillAddMenus()
    }

    private func entry(at path: [Int]) -> Entry? {
        var level = roots
        var found: Entry?
        for index in path {
            guard level.indices.contains(index) else { return nil }
            found = level[index]
            level = level[index].children
        }
        return found
    }

    private var selectedPath: [Int]? {
        (outline.item(atRow: outline.selectedRow) as? Entry)?.path
    }

    private func commit(select path: [Int]? = nil) {
        save(tree)
        reload(select: path)
    }

    private func fillAddMenus() {
        func flatten(_ nodes: [ActionNode]) -> [String] {
            nodes.flatMap { node -> [String] in
                switch node.kind {
                case .script(let path): [path]
                case .folder(let kids): flatten(kids)
                case .builtin: []
                }
            }
        }
        addScriptButton.removeAllItems()
        addScriptButton.addItem(withTitle: "Add Script")
        for path in flatten(scripts()) { addScriptButton.addItem(withTitle: path) }
        addScriptButton.menu?.items.forEach { if $0 !== addScriptButton.menu?.items.first { $0.target = self; $0.action = #selector(addScript(_:)) } }

        addBuiltinButton.removeAllItems()
        addBuiltinButton.addItem(withTitle: "Add Built-in")
        for action in ClipAction.allCases {
            let item = NSMenuItem(title: action.title, action: #selector(addBuiltin(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action.rawValue
            addBuiltinButton.menu?.addItem(item)
        }
    }

    /// New entries go into the selected folder, or just below the selected entry, or at the end.
    private func add(_ node: ActionNode) {
        var folder: [Int] = []
        var index = tree.count
        if let path = selectedPath, let selected = ActionTreeEdit.node(at: path, in: tree) {
            if case .folder(let kids) = selected.kind {
                folder = path
                index = kids.count
            } else {
                folder = Array(path.dropLast())
                index = path.last! + 1
            }
        }
        ActionTreeEdit.insert(node, into: folder, at: index, in: &tree)
        commit(select: folder + [index])
    }

    // MARK: - Actions

    @objc private func addScript(_ sender: NSMenuItem) {
        let path = sender.title
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        add(ActionNode(title: name, kind: .script(path)))
    }

    @objc private func addBuiltin(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = ClipAction(rawValue: raw) else { return }
        add(ActionNode(title: action.title, kind: .builtin(action)))
    }

    @objc private func addFolder() {
        add(ActionNode(title: "New Folder", kind: .folder([])))
    }

    @objc private func removeSelected() {
        guard let path = selectedPath else { return }
        ActionTreeEdit.remove(path, in: &tree)
        commit()
    }

    @objc private func moveUp() { moveSelected { ActionTreeEdit.move($0, by: -1, in: &$1) } }
    @objc private func moveDown() { moveSelected { ActionTreeEdit.move($0, by: 1, in: &$1) } }
    @objc private func indent() { moveSelected { ActionTreeEdit.indent($0, in: &$1) } }
    @objc private func outdent() { moveSelected { ActionTreeEdit.outdent($0, in: &$1) } }

    private func moveSelected(_ edit: ([Int], inout [ActionNode]) -> [Int]?) {
        guard let path = selectedPath, let moved = edit(path, &tree) else { NSSound.beep(); return }
        commit(select: moved)
    }

    @objc private func reset() {
        let alert = NSAlert()
        alert.messageText = "Reset the action menu?"
        alert.informativeText = "Your list is replaced by Paste as Plain Text, every script under Scripts, and Remove."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        tree = defaults()
        commit()
    }

    // MARK: - Outline

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? Entry)?.children.count ?? roots.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? Entry)?.children[index] ?? roots[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if case .folder = (item as? Entry)?.node.kind { return true }
        return false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let entry = item as? Entry else { return nil }
        let field = NSTextField(string: entry.node.title)
        field.isBordered = false
        field.drawsBackground = false
        field.isEditable = true
        field.delegate = self
        field.identifier = NSUserInterfaceItemIdentifier("title")
        let kind: String
        switch entry.node.kind {
        case .builtin: kind = "built-in"
        case .script(let path): kind = path
        case .folder: kind = "folder"
        }
        field.toolTip = kind
        return field
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        let row = outline.row(for: field)
        guard row >= 0, let entry = outline.item(atRow: row) as? Entry else { return }
        let title = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, title != entry.node.title else { field.stringValue = entry.node.title; return }
        ActionTreeEdit.rename(entry.path, to: title, in: &tree)
        commit(select: entry.path)
    }
}
