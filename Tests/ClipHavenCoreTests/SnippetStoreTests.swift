import XCTest
@testable import ClipHavenCore

final class SnippetStoreTests: XCTestCase {
    private var dir: URL!
    private var url: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("SnippetStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("history.sqlite")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testFoldersAndSnippetsKeepInsertionOrder() throws {
        let store = try SnippetStore(url: url)
        let a = try store.addFolder(title: "A")
        let b = try store.addFolder(title: "B")
        try store.addSnippet(folderID: a, title: "one", content: "1")
        try store.addSnippet(folderID: a, title: "two", content: "2")
        try store.addSnippet(folderID: b, title: "three", content: "3")

        let folders = try store.folders()
        XCTAssertEqual(folders.map(\.title), ["A", "B"])
        XCTAssertEqual(folders[0].snippets.map(\.title), ["one", "two"])
        XCTAssertEqual(folders[1].snippets.map(\.content), ["3"])
    }

    func testUpdateFolderAndSnippet() throws {
        let store = try SnippetStore(url: url)
        let f = try store.addFolder(title: "A")
        let s = try store.addSnippet(folderID: f, title: "one", content: "1")
        try store.updateFolder(id: f, title: "A2", enabled: false)
        try store.updateSnippet(id: s, title: "uno", content: "uno!", enabled: false)

        let folder = try XCTUnwrap(store.folders().first)
        XCTAssertEqual(folder.title, "A2")
        XCTAssertFalse(folder.enabled)
        XCTAssertEqual(folder.snippets, [Snippet(id: s, title: "uno", content: "uno!", enabled: false, secret: nil, requiresAuth: false)])
    }

    func testDeletingAFolderDeletesItsSnippets() throws {
        let store = try SnippetStore(url: url)
        let f = try store.addFolder(title: "A")
        try store.addSnippet(folderID: f, title: "one", content: "1")
        try store.deleteFolder(id: f)
        XCTAssertEqual(try store.folders(), [])
        XCTAssertEqual(try store.snippetCount(), 0)
    }

    func testDeleteSnippet() throws {
        let store = try SnippetStore(url: url)
        let f = try store.addFolder(title: "A")
        let one = try store.addSnippet(folderID: f, title: "one", content: "1")
        try store.addSnippet(folderID: f, title: "two", content: "2")
        try store.deleteSnippet(id: one)
        XCTAssertEqual(try store.folders()[0].snippets.map(\.title), ["two"])
    }

    func testReorderFoldersAndSnippets() throws {
        let store = try SnippetStore(url: url)
        let a = try store.addFolder(title: "A")
        let b = try store.addFolder(title: "B")
        let s1 = try store.addSnippet(folderID: a, title: "one", content: "1")
        let s2 = try store.addSnippet(folderID: a, title: "two", content: "2")

        try store.reorderFolders([b, a])
        try store.reorderSnippets([s2, s1], in: a)

        let folders = try store.folders()
        XCTAssertEqual(folders.map(\.title), ["B", "A"])
        XCTAssertEqual(folders[1].snippets.map(\.title), ["two", "one"])
    }

    func testNewItemsGoAfterAReorder() throws {
        let store = try SnippetStore(url: url)
        let a = try store.addFolder(title: "A")
        let b = try store.addFolder(title: "B")
        try store.reorderFolders([b, a])
        try store.addFolder(title: "C")
        XCTAssertEqual(try store.folders().map(\.title), ["B", "A", "C"])
    }

    func testImportAddsFoldersAfterWhatIsThereAndCounts() throws {
        let store = try SnippetStore(url: url)
        try store.addFolder(title: "Mine")
        let imported = [
            ImportedFolder(title: "Greetings", enabled: true, snippets: [
                ImportedSnippet(title: "hi", content: "Hello", enabled: true),
                ImportedSnippet(title: "off", content: "x", enabled: false),
            ]),
            ImportedFolder(title: "Empty", enabled: false, snippets: []),
        ]
        let counts = try store.importFolders(imported)
        XCTAssertEqual(counts, ImportCounts(folders: 2, snippets: 2))
        let folders = try store.folders()
        XCTAssertEqual(folders.map(\.title), ["Mine", "Greetings", "Empty"])
        XCTAssertEqual(folders[1].snippets.map(\.enabled), [true, false])
        XCTAssertFalse(folders[2].enabled)
    }

    func testPersistsAcrossReopen() throws {
        let store = try SnippetStore(url: url)
        let f = try store.addFolder(title: "A")
        try store.addSnippet(folderID: f, title: "one", content: "1")
        let reopened = try SnippetStore(url: url)
        XCTAssertEqual(try reopened.folders().first?.snippets.first?.content, "1")
    }

    func testSharesTheHistoryFileWithoutDisturbingIt() throws {
        let history = try HistoryStore(url: url)
        try history.insert([Representation(type: "public.utf8-plain-text", data: Data("clip".utf8))], title: "clip")
        let snippets = try SnippetStore(url: url)
        try snippets.addFolder(title: "A")
        try history.insert([Representation(type: "public.utf8-plain-text", data: Data("clip2".utf8))], title: "clip2")
        XCTAssertEqual(try history.count(), 2)
        XCTAssertEqual(try snippets.folders().count, 1)
    }

    func testMenuSummariesSkipDisabledFoldersAndSnippets() throws {
        let store = try SnippetStore(url: url)
        let on = try store.addFolder(title: "On")
        let off = try store.addFolder(title: "Off")
        try store.addSnippet(folderID: on, title: "shown", content: "1")
        let hidden = try store.addSnippet(folderID: on, title: "hidden", content: "2")
        try store.addSnippet(folderID: off, title: "never", content: "3")
        try store.updateSnippet(id: hidden, title: "hidden", content: "2", enabled: false)
        try store.updateFolder(id: off, title: "Off", enabled: false)

        let summaries = try store.menuSummaries()
        XCTAssertEqual(summaries.map(\.title), ["On"])
        XCTAssertEqual(summaries[0].snippets.map(\.title), ["shown"])
    }

    func testSnippetContentForPasting() throws {
        let store = try SnippetStore(url: url)
        let f = try store.addFolder(title: "A")
        let s = try store.addSnippet(folderID: f, title: "one", content: "body")
        XCTAssertEqual(try store.snippet(id: s)?.content, "body")
        XCTAssertNil(try store.snippet(id: 999))
    }
}
