import XCTest
@testable import ClipHavenCore

final class MenuModelTests: XCTestCase {
    private func clips(_ n: Int) -> [ClipSummary] {
        // Newest first, as the store returns them: clip n is the newest.
        (0..<n).map { i in ClipSummary(id: Int64(n - i), title: "c\(n - i)", primaryType: "public.utf8-plain-text") }
    }

    private func build(_ n: Int, snippets: [SnippetFolderSummary] = []) -> [MenuEntry] {
        MenuModel.build(clips: clips(n), snippetFolders: snippets, layout: MenuLayout())
    }

    private func items(_ entries: [MenuEntry]) -> [MenuItemEntry] {
        entries.compactMap { if case .item(let item) = $0 { item } else { nil } }
    }

    private func folders(_ entries: [MenuEntry]) -> [(title: String, items: [MenuItemEntry])] {
        entries.compactMap { if case .folder(let title, let items) = $0 { (title, items) } else { nil } }
    }

    func testEmptyHistoryHasNoItems() {
        XCTAssertEqual(build(0), [])
    }

    func testTwentyClipsAllInlineAndNumbered() {
        let entries = build(20)
        XCTAssertEqual(items(entries).count, 20)
        XCTAssertTrue(folders(entries).isEmpty)
        XCTAssertEqual(items(entries).first, MenuItemEntry(target: .clip(20), title: "1. c20"))
        XCTAssertEqual(items(entries).last, MenuItemEntry(target: .clip(1), title: "20. c1"))
    }

    func testTwentyFirstClipStartsAFolderNumberedFromOne() {
        let entries = build(21)
        XCTAssertEqual(items(entries).count, 20)
        let folder = try! XCTUnwrap(folders(entries).first)
        XCTAssertEqual(folder.title, "21 - 21")
        XCTAssertEqual(folder.items, [MenuItemEntry(target: .clip(1), title: "1. c1")])
    }

    func testOneHundredTwentyClipsMakeFoldersOfTwentyFive() {
        let entries = build(120)
        XCTAssertEqual(items(entries).count, 20)
        XCTAssertEqual(folders(entries).map(\.title), ["21 - 45", "46 - 70", "71 - 95", "96 - 120"])
        XCTAssertEqual(folders(entries).map(\.items.count), [25, 25, 25, 25])
        XCTAssertEqual(folders(entries)[1].items.first?.title, "1. c75")
    }

    func testSnippetFoldersComeFirstThenASeparator() {
        let snippets = [SnippetFolderSummary(title: "Work", snippets: [SnippetSummary(id: 7, title: "Signature")])]
        let entries = build(2, snippets: snippets)
        XCTAssertEqual(entries.first, .folder(title: "Work", items: [MenuItemEntry(target: .snippet(7), title: "Signature")]))
        XCTAssertEqual(entries[1], .separator)
        XCTAssertEqual(items(entries).map(\.target), [.clip(2), .clip(1)])
    }

    func testNoSeparatorWithoutSnippets() {
        XCTAssertFalse(build(3).contains(.separator))
    }

    func testLongTitlesAreTrimmedToTheLayoutLength() {
        let long = ClipSummary(id: 1, title: "abcdefghijklmnopqrstuvwxyz", primaryType: "public.utf8-plain-text")
        let entries = MenuModel.build(clips: [long], snippetFolders: [], layout: MenuLayout())
        XCTAssertEqual(items(entries).first?.title, "1. abcdefghijklmnopqrs…")
        XCTAssertEqual(MenuModel.trim("abcdefghijklmnopqrst", to: 20), "abcdefghijklmnopqrst")
    }

    func testUnnumberedLayout() {
        var layout = MenuLayout()
        layout.numbered = false
        let entries = MenuModel.build(clips: clips(1), snippetFolders: [], layout: layout)
        XCTAssertEqual(items(entries).first?.title, "c1")
    }

    func testSubfoldersBecomeSubmenusAboveTheFoldersOwnSnippets() {
        let inner = SnippetFolderSummary(title: "Email", snippets: [SnippetSummary(id: 2, title: "Signature")])
        let outer = SnippetFolderSummary(title: "Work", snippets: [SnippetSummary(id: 1, title: "Address")], subfolders: [inner])
        let entries = build(0, snippets: [outer])
        XCTAssertEqual(entries, [.folderWithSubfolders(
            title: "Work",
            items: [MenuItemEntry(target: .snippet(1), title: "Address")],
            subfolders: [MenuSubfolder(title: "Email", items: [MenuItemEntry(target: .snippet(2), title: "Signature")])])])
    }

    func testAFolderWithoutSubfoldersStaysAPlainFolder() {
        let entries = build(0, snippets: [SnippetFolderSummary(title: "Work", snippets: [SnippetSummary(id: 7, title: "Signature")])])
        XCTAssertEqual(entries, [.folder(title: "Work", items: [MenuItemEntry(target: .snippet(7), title: "Signature")])])
    }
}
