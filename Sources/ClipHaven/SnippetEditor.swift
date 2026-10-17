import AppKit
import ClipHavenCore

/// The snippet editor: folders on the left, the folder's snippets in the middle, the selected
/// snippet's text on the right. Every edit is written to the store at once.
@MainActor
final class SnippetEditor: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate {
    private let store: SnippetStore
    private let onChange: () -> Void
    private var folders: [SnippetFolder] = []
    private var selectedFolderID: Int64?
    private var selectedSnippetID: Int64?

    private var window: NSWindow?
    private let folderTable = NSTableView()
    private let snippetTable = NSTableView()
    private let contentView = NSTextView()

    init(store: SnippetStore, onChange: @escaping () -> Void) {
        self.store = store
        self.onChange = onChange
    }

    func show() {
        if window == nil { build() }
        reload()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Window

    private func build() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 440),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "ClipHaven Snippets"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        configure(folderTable, titleHeader: "Folder")
        configure(snippetTable, titleHeader: "Snippet")

        contentView.isRichText = false
        contentView.isAutomaticQuoteSubstitutionEnabled = false
        contentView.isAutomaticDashSubstitutionEnabled = false
        contentView.isAutomaticTextReplacementEnabled = false
        contentView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        contentView.allowsUndo = true
        contentView.delegate = self
        contentView.isVerticallyResizable = true
        contentView.autoresizingMask = [.width]
        let contentScroll = NSScrollView()
        contentScroll.documentView = contentView
        contentScroll.hasVerticalScroller = true
        contentScroll.borderType = .bezelBorder

        let panes = NSStackView(views: [
            pane(folderTable, add: #selector(addFolder), remove: #selector(deleteFolder), up: #selector(moveFolderUp), down: #selector(moveFolderDown)),
            pane(snippetTable, add: #selector(addSnippet), remove: #selector(deleteSnippet), up: #selector(moveSnippetUp), down: #selector(moveSnippetDown)),
            contentScroll,
        ])
        panes.orientation = .horizontal
        panes.distribution = .fill
        panes.spacing = 12
        panes.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        panes.arrangedSubviews[0].widthAnchor.constraint(equalToConstant: 190).isActive = true
        panes.arrangedSubviews[1].widthAnchor.constraint(equalToConstant: 210).isActive = true
        window.contentView = panes
        self.window = window
    }

    private func configure(_ table: NSTableView, titleHeader: String) {
        let on = NSTableColumn(identifier: .init("enabled"))
        on.title = "On"
        on.width = 28
        on.minWidth = 28
        on.maxWidth = 28
        let cell = NSButtonCell()
        cell.setButtonType(.switch)
        cell.title = ""
        on.dataCell = cell
        let title = NSTableColumn(identifier: .init("title"))
        title.title = titleHeader
        title.isEditable = true
        table.addTableColumn(on)
        table.addTableColumn(title)
        table.dataSource = self
        table.delegate = self
        table.allowsEmptySelection = true
    }

    private func pane(_ table: NSTableView, add: Selector, remove: Selector, up: Selector, down: Selector) -> NSView {
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        func button(_ title: String, _ action: Selector) -> NSButton {
            let b = NSButton(title: title, target: self, action: action)
            b.bezelStyle = .smallSquare
            return b
        }
        let buttons = NSStackView(views: [button("+", add), button("−", remove), button("▲", up), button("▼", down)])
        buttons.spacing = 4
        let column = NSStackView(views: [scroll, buttons])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 6
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        scroll.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        return column
    }

    func windowWillClose(_ notification: Notification) {
        saveContent()
        onChange()
    }

    // MARK: - Data

    private var selectedFolder: SnippetFolder? { folders.first { $0.id == selectedFolderID } }
    private var snippets: [Snippet] { selectedFolder?.snippets ?? [] }

    private func reload() {
        folders = (try? store.folders()) ?? []
        if selectedFolder == nil { selectedFolderID = folders.first?.id }
        if !snippets.contains(where: { $0.id == selectedSnippetID }) { selectedSnippetID = snippets.first?.id }
        folderTable.reloadData()
        snippetTable.reloadData()
        select(folderTable, row: folders.firstIndex { $0.id == selectedFolderID })
        select(snippetTable, row: snippets.firstIndex { $0.id == selectedSnippetID })
        showContent()
    }

    private func select(_ table: NSTableView, row: Int?) {
        if let row { table.selectRowIndexes([row], byExtendingSelection: false) } else { table.deselectAll(nil) }
    }

    private func showContent() {
        let snippet = snippets.first { $0.id == selectedSnippetID }
        contentView.string = snippet?.content ?? ""
        contentView.isEditable = snippet != nil
    }

    /// Writes the text pane back to the selected snippet.
    private func saveContent() {
        guard let snippet = snippets.first(where: { $0.id == selectedSnippetID }), snippet.content != contentView.string else { return }
        try? store.updateSnippet(id: snippet.id, title: snippet.title, content: contentView.string, enabled: snippet.enabled)
        folders = (try? store.folders()) ?? folders
    }

    func textDidChange(_ notification: Notification) {
        saveContent()
    }

    // MARK: - Tables

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === folderTable ? folders.count : snippets.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor column: NSTableColumn?, row: Int) -> Any? {
        let isOn = column?.identifier.rawValue == "enabled"
        if tableView === folderTable {
            guard folders.indices.contains(row) else { return nil }
            return isOn ? folders[row].enabled : folders[row].title
        }
        guard snippets.indices.contains(row) else { return nil }
        return isOn ? snippets[row].enabled : snippets[row].title
    }

    func tableView(_ tableView: NSTableView, setObjectValue value: Any?, for column: NSTableColumn?, row: Int) {
        let isOn = column?.identifier.rawValue == "enabled"
        if tableView === folderTable, folders.indices.contains(row) {
            let folder = folders[row]
            try? store.updateFolder(id: folder.id, title: isOn ? folder.title : (value as? String ?? folder.title),
                                    enabled: isOn ? Self.flag(value, else: folder.enabled) : folder.enabled)
        } else if tableView === snippetTable, snippets.indices.contains(row) {
            let snippet = snippets[row]
            try? store.updateSnippet(id: snippet.id, title: isOn ? snippet.title : (value as? String ?? snippet.title),
                                     content: snippet.content, enabled: isOn ? Self.flag(value, else: snippet.enabled) : snippet.enabled)
        }
        reload()
        onChange()
    }

    /// A checkbox cell hands back an NSNumber.
    private static func flag(_ value: Any?, else fallback: Bool) -> Bool {
        (value as? NSNumber)?.boolValue ?? fallback
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table = notification.object as? NSTableView else { return }
        saveContent()
        if table === folderTable {
            selectedFolderID = folders.indices.contains(folderTable.selectedRow) ? folders[folderTable.selectedRow].id : nil
            selectedSnippetID = snippets.first?.id
            snippetTable.reloadData()
            select(snippetTable, row: snippets.isEmpty ? nil : 0)
        } else {
            selectedSnippetID = snippets.indices.contains(snippetTable.selectedRow) ? snippets[snippetTable.selectedRow].id : nil
        }
        showContent()
    }

    // MARK: - Buttons

    @objc private func addFolder() {
        saveContent()
        selectedFolderID = try? store.addFolder(title: "untitled folder")
        selectedSnippetID = nil
        changed()
    }

    @objc private func deleteFolder() {
        guard let id = selectedFolderID else { return }
        try? store.deleteFolder(id: id)
        selectedFolderID = nil
        selectedSnippetID = nil
        changed()
    }

    @objc private func addSnippet() {
        guard let folder = selectedFolderID else { return }
        saveContent()
        selectedSnippetID = try? store.addSnippet(folderID: folder, title: "untitled snippet", content: "")
        changed()
    }

    @objc private func deleteSnippet() {
        guard let id = selectedSnippetID else { return }
        try? store.deleteSnippet(id: id)
        selectedSnippetID = nil
        changed()
    }

    @objc private func moveFolderUp() { moveFolder(by: -1) }
    @objc private func moveFolderDown() { moveFolder(by: 1) }
    @objc private func moveSnippetUp() { moveSnippet(by: -1) }
    @objc private func moveSnippetDown() { moveSnippet(by: 1) }

    private func moveFolder(by offset: Int) {
        guard let id = selectedFolderID, let from = folders.firstIndex(where: { $0.id == id }),
              folders.indices.contains(from + offset) else { return }
        var ids = folders.map(\.id)
        ids.swapAt(from, from + offset)
        try? store.reorderFolders(ids)
        changed()
    }

    private func moveSnippet(by offset: Int) {
        guard let folder = selectedFolderID, let id = selectedSnippetID, let from = snippets.firstIndex(where: { $0.id == id }),
              snippets.indices.contains(from + offset) else { return }
        var ids = snippets.map(\.id)
        ids.swapAt(from, from + offset)
        try? store.reorderSnippets(ids, in: folder)
        changed()
    }

    private func changed() {
        reload()
        onChange()
    }
}
