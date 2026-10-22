import XCTest
@testable import ClipHavenCore

final class MenuSearchTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("MenuSearch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func text(_ s: String) -> [Representation] { [Representation(type: "public.utf8-plain-text", data: Data(s.utf8))] }

    // MARK: history search

    func testHistorySearchFindsTitleAndBodyCaseInsensitivelyNewestFirst() throws {
        let store = try HistoryStore(url: dir.appendingPathComponent("h.sqlite"))
        let a = try XCTUnwrap(store.insert(text("first Invoice body"), title: "first Invoice body"))
        _ = try store.insert(text("unrelated"), title: "unrelated")
        let c = try XCTUnwrap(store.insert(text("long text with the word invoice deep inside"), title: "long text with the…"))
        XCTAssertEqual(try store.search(words: ["invoice"], limit: 10), [c, a])
    }

    func testHistorySearchNeedsEveryWord() throws {
        let store = try HistoryStore(url: dir.appendingPathComponent("h.sqlite"))
        let both = try XCTUnwrap(store.insert(text("red apple"), title: "red apple"))
        _ = try store.insert(text("red car"), title: "red car")
        XCTAssertEqual(try store.search(words: ["apple", "red"], limit: 10), [both])
    }

    func testPercentAndUnderscoreMatchLiterally() throws {
        let store = try HistoryStore(url: dir.appendingPathComponent("h.sqlite"))
        let hit = try XCTUnwrap(store.insert(text("100% done"), title: "100% done"))
        _ = try store.insert(text("1000 done"), title: "1000 done")
        XCTAssertEqual(try store.search(words: ["0% d"], limit: 10), [hit])
        XCTAssertEqual(try store.search(words: ["_"], limit: 10), [])
    }

    func testHistorySearchIgnoresImageBytes() throws {
        let store = try HistoryStore(url: dir.appendingPathComponent("h.sqlite"))
        _ = try store.insert([Representation(type: "public.png", data: Data("needle".utf8))], title: "Image")
        XCTAssertEqual(try store.search(words: ["needle"], limit: 10), [])
    }

    // MARK: result paths

    private func clips(_ n: Int) -> [ClipSummary] {
        (0..<n).map { ClipSummary(id: Int64(n - $0), title: "c\(n - $0)", primaryType: "public.utf8-plain-text") }
    }

    func testClipPathsFollowTheMenuLayout() {
        let all = clips(50) // ids 50...1, newest first
        let results = MenuSearch.results(query: "c", clips: all, matchingClipIDs: [50, 31, 30, 6, 1],
                                         snippetFolders: [], layout: MenuLayout())
        XCTAssertEqual(results.map(\.path), [
            "History › #1",            // index 0
            "History › #20",           // id 31 is index 19
            "History › 21 - 45 › #1",  // id 30 is index 20
            "History › 21 - 45 › #25", // id 6 is index 44
            "History › 46 - 50 › #5",  // id 1 is index 49
        ])
    }

    func testSnippetPathsAndMatchingOnContent() throws {
        let store = try SnippetStore(url: dir.appendingPathComponent("s.sqlite"))
        let work = try store.addFolder(title: "Work")
        let sub = try store.addFolder(title: "Servers", parentID: work)
        let top = try store.addSnippet(folderID: work, title: "Greeting", content: "Dear customer")
        let nested = try store.addSnippet(folderID: sub, title: "Host", content: "db01.example.com")
        let folders = try store.folders()

        let byContent = MenuSearch.results(query: "example.com", clips: [], matchingClipIDs: [], snippetFolders: folders, layout: MenuLayout())
        XCTAssertEqual(byContent, [SearchResult(target: .snippet(nested), title: "Host", path: "Snippets › Work › Servers")])

        let byFolder = MenuSearch.results(query: "work greet", clips: [], matchingClipIDs: [], snippetFolders: folders, layout: MenuLayout())
        XCTAssertEqual(byFolder, [SearchResult(target: .snippet(top), title: "Greeting", path: "Snippets › Work")])
    }

    func testLockedSnippetMatchesOnTitleButNeverOnContent() throws {
        let store = try SnippetStore(url: dir.appendingPathComponent("s.sqlite"))
        let folder = try store.addFolder(title: "Logins")
        let touch = try store.addSnippet(folderID: folder, title: "Bank", content: "hunter2")
        try store.setRequiresAuth(id: touch, true)
        let folders = try store.folders()
        XCTAssertEqual(MenuSearch.results(query: "hunter2", clips: [], matchingClipIDs: [], snippetFolders: folders, layout: MenuLayout()), [])
        let byTitle = MenuSearch.results(query: "bank", clips: [], matchingClipIDs: [], snippetFolders: folders, layout: MenuLayout())
        XCTAssertEqual(byTitle.map(\.isLocked), [true])
    }

    func testDisabledSnippetsAndFoldersAreSkippedAndBlankQueryIsEmpty() throws {
        let store = try SnippetStore(url: dir.appendingPathComponent("s.sqlite"))
        let off = try store.addFolder(title: "Off", enabled: false)
        _ = try store.addSnippet(folderID: off, title: "Hidden", content: "x")
        let on = try store.addFolder(title: "On")
        _ = try store.addSnippet(folderID: on, title: "Gone", content: "x", enabled: false)
        let folders = try store.folders()
        XCTAssertEqual(MenuSearch.results(query: "x", clips: [], matchingClipIDs: [], snippetFolders: folders, layout: MenuLayout()), [])
        XCTAssertEqual(MenuSearch.results(query: "  ", clips: [], matchingClipIDs: [], snippetFolders: folders, layout: MenuLayout()), [])
    }

    func testScopeNamesOnlyAndContentsOnly() throws {
        let h = try HistoryStore(url: dir.appendingPathComponent("h2.sqlite"))
        let named = try XCTUnwrap(h.insert(text("body without it"), title: "report title"))
        let inBody = try XCTUnwrap(h.insert(text("the report is here"), title: "the…"))
        XCTAssertEqual(try h.search(words: ["report"], scope: .names, limit: 10), [named])
        XCTAssertEqual(try h.search(words: ["report"], scope: .contents, limit: 10), [inBody])
        XCTAssertEqual(try h.search(words: ["report"], scope: .all, limit: 10), [inBody, named])

        let store = try SnippetStore(url: dir.appendingPathComponent("s.sqlite"))
        let folder = try store.addFolder(title: "Docs")
        let byTitle = try store.addSnippet(folderID: folder, title: "Invoice", content: "nothing")
        let byBody = try store.addSnippet(folderID: folder, title: "Other", content: "see invoice")
        let folders = try store.folders()
        func ids(_ scope: SearchScope, _ q: String) -> [MenuTarget] {
            MenuSearch.results(query: q, clips: [], matchingClipIDs: [], snippetFolders: folders, layout: MenuLayout(), scope: scope).map(\.target)
        }
        XCTAssertEqual(ids(.names, "invoice"), [.snippet(byTitle)])
        XCTAssertEqual(ids(.contents, "invoice"), [.snippet(byBody)])
        XCTAssertEqual(ids(.all, "invoice"), [.snippet(byTitle), .snippet(byBody)])
        XCTAssertEqual(ids(.names, "docs").count, 2) // the folder name counts as a name
        XCTAssertEqual(ids(.contents, "docs"), [])
    }
}
