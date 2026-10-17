import Foundation
import XCTest
@testable import ClipHavenCore

@MainActor
final class ActionListTests: XCTestCase {
    private var dir: URL!
    private var store: HistoryStore!
    private var log: PasteLog!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ActionListTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = try HistoryStore(url: dir.appendingPathComponent("history.sqlite"))
        log = PasteLog()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func text(_ s: String) -> [Representation] {
        [Representation(type: "public.utf8-plain-text", data: Data(s.utf8))]
    }

    private func service(user: URL? = nil, prompt: @escaping @Sendable (String) -> String? = { _ in nil }) -> ActionService {
        let bundled = ScriptRunnerTests.bundled
        let folders = (user.map { [$0.appendingPathComponent("action")] } ?? []) + [bundled.appendingPathComponent("action")]
        let runner = ScriptRunner(libFolders: (user.map { [$0.appendingPathComponent("lib")] } ?? []) + [bundled.appendingPathComponent("lib")], prompt: prompt)
        return ActionService(paster: Paster(store: store, writer: log, poster: log, autoPaste: true),
                             store: store, runner: runner, actionFolders: folders)
    }

    private func assertThrows(_ body: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await body(); XCTFail("expected an error", file: file, line: line) } catch {}
    }

    private func pastedText() -> String? {
        log.written.last?.first { $0.type == "public.utf8-plain-text" }.map { String(decoding: $0.data, as: UTF8.self) }
    }

    // MARK: - Importing ClipMenu's actions.plist

    private func plist(_ nodes: [[String: Any]]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: nodes, format: .xml, options: 0)
    }

    private func leaf(_ title: String, _ action: [String: Any]) -> [String: Any] {
        ["nodeTitle": title, "isLeaf": true, "children": [Any](), "action": action]
    }

    func testImportReadsBuiltinsScriptsAndFolders() throws {
        let installed = "/Applications/Utilities/ClipMenu.app/Contents/Resources/script/action"
        let data = try plist([
            leaf("Paste as Plain Text", ["type": "builtin", "name": "pasteAsPlainText:"]),
            ["nodeTitle": "Case", "isLeaf": false, "children": [
                leaf("Capitalize.js", ["type": "js", "path": "\(installed)/Case/Capitalize.js"]),
            ]],
            leaf("Remove", ["type": "builtin", "name": "remove:"]),
        ])
        XCTAssertEqual(try ActionList.importClipMenu(data), [
            ActionNode(title: "Paste as Plain Text", kind: .builtin(.pasteAsPlainText)),
            ActionNode(title: "Case", kind: .folder([ActionNode(title: "Capitalize", kind: .script("Case/Capitalize.js"))])),
            ActionNode(title: "Remove", kind: .builtin(.remove)),
        ])
    }

    func testImportKeepsAUserScriptByItsFileName() throws {
        let data = try plist([leaf("mine.js", ["type": "js", "path": "/Users/x/Library/Application Support/ClipMenu/script/action/Mine/mine.js"])])
        XCTAssertEqual(try ActionList.importClipMenu(data), [ActionNode(title: "mine", kind: .script("Mine/mine.js"))])
    }

    func testImportDropsUnknownBuiltinsAndEmptyFolders() throws {
        let data = try plist([
            leaf("Speak", ["type": "builtin", "name": "speak:"]),
            ["nodeTitle": "Empty", "isLeaf": false, "children": [Any]()],
        ])
        XCTAssertEqual(try ActionList.importClipMenu(data), [])
    }

    func testImportFileBacksUpTheOriginalFirst() throws {
        let source = dir.appendingPathComponent("actions.plist")
        try plist([leaf("Remove", ["type": "builtin", "name": "remove:"])]).write(to: source)
        let backups = dir.appendingPathComponent("backups")
        let result = try ActionList.importFile(at: source, backupDirectory: backups)
        XCTAssertEqual(result.tree, [ActionNode(title: "Remove", kind: .builtin(.remove))])
        XCTAssertEqual(try Data(contentsOf: result.backup), try Data(contentsOf: source))
        XCTAssertTrue(result.backup.lastPathComponent.hasPrefix("actions-"))
    }

    func testImportOfGarbageThrows() {
        XCTAssertThrowsError(try ActionList.importClipMenu(Data("not a plist".utf8)))
    }

    // MARK: - Finding scripts, the default list, and the saved file

    func testDiscoverScriptsWalksFoldersAndUserShadowsBundled() throws {
        let user = dir.appendingPathComponent("user/action")
        try FileManager.default.createDirectory(at: user.appendingPathComponent("Mine"), withIntermediateDirectories: true)
        try "return clipText;".write(to: user.appendingPathComponent("Mine/Same.js"), atomically: true, encoding: .utf8)
        try "return 'user';".write(to: user.appendingPathComponent("Reverse.js"), atomically: true, encoding: .utf8)

        let found = ActionList.discoverScripts(in: [user, ScriptRunnerTests.bundled.appendingPathComponent("action")])
        func paths(_ nodes: [ActionNode]) -> [String] {
            nodes.flatMap { node -> [String] in
                switch node.kind {
                case .script(let path): [path]
                case .folder(let children): paths(children)
                case .builtin: []
                }
            }
        }
        let all = paths(found)
        XCTAssertEqual(all.count, 48) // 47 bundled + Mine/Same.js; Reverse.js appears once
        XCTAssertEqual(all.filter { $0 == "Reverse.js" }.count, 1)
        XCTAssertTrue(all.contains("Mine/Same.js"))
    }

    func testDefaultListHasTheBuiltinsAndAScriptsFolder() {
        let scripts = [ActionNode(title: "Reverse", kind: .script("Reverse.js"))]
        let list = ActionList.defaultTree(scripts: scripts)
        XCTAssertEqual(list.first, ActionNode(title: "Paste as Plain Text", kind: .builtin(.pasteAsPlainText)))
        XCTAssertEqual(list.last, ActionNode(title: "Remove", kind: .builtin(.remove)))
        XCTAssertTrue(list.contains(ActionNode(title: "Scripts", kind: .folder(scripts))))
    }

    func testStoreRoundTripsAndReportsMissing() throws {
        let file = dir.appendingPathComponent("actions.json")
        let actions = ActionStore(url: file)
        XCTAssertNil(try actions.load())
        let tree = [ActionNode(title: "Case", kind: .folder([ActionNode(title: "Upper", kind: .script("Case/UPPERCASE.js"))])),
                    ActionNode(title: "Remove", kind: .builtin(.remove))]
        try actions.save(tree)
        XCTAssertEqual(try ActionStore(url: file).load(), tree)
    }

    // MARK: - What a clip is offered

    func testVisibleHidesTextActionsForAnImageAndEmptyFolders() {
        let tiff = [Representation(type: "public.tiff", data: Data([1]))]
        let tree = [
            ActionNode(title: "Paste as Plain Text", kind: .builtin(.pasteAsPlainText)),
            ActionNode(title: "Case", kind: .folder([ActionNode(title: "Upper", kind: .script("Case/UPPERCASE.js"))])),
            ActionNode(title: "Remove", kind: .builtin(.remove)),
        ]
        XCTAssertEqual(ActionList.visible(tree, for: tiff), [ActionNode(title: "Remove", kind: .builtin(.remove))])
        XCTAssertEqual(ActionList.visible(tree, for: text("x")), tree)
    }

    // MARK: - Running an action

    func testScriptActionPastesTheResult() async throws {
        let id = try XCTUnwrap(try store.insert(text("abc"), title: "abc"))
        try await service().perform(ActionNode(title: "Reverse", kind: .script("Reverse.js")), clipID: id)
        XCTAssertEqual(pastedText(), "cba")
        XCTAssertEqual(log.events, ["write", "cmd-v"])
    }

    func testScriptActionOnAClipWithoutTextDoesNothing() async throws {
        let id = try XCTUnwrap(try store.insert([Representation(type: "public.tiff", data: Data([1]))], title: "img"))
        try await service().perform(ActionNode(title: "Reverse", kind: .script("Reverse.js")), clipID: id)
        XCTAssertTrue(log.events.isEmpty)
    }

    func testAFailingScriptThrowsAndPastesNothing() async throws {
        let user = dir.appendingPathComponent("user")
        try FileManager.default.createDirectory(at: user.appendingPathComponent("action"), withIntermediateDirectories: true)
        try "throw new Error('bad');".write(to: user.appendingPathComponent("action/Bad.js"), atomically: true, encoding: .utf8)
        let id = try XCTUnwrap(try store.insert(text("abc"), title: "abc"))
        await assertThrows { try await self.service(user: user).perform(ActionNode(title: "Bad", kind: .script("Bad.js")), clipID: id) }
        XCTAssertTrue(log.events.isEmpty)
    }

    func testAScriptPathThatClimbsOutIsRefused() async throws {
        let id = try XCTUnwrap(try store.insert(text("abc"), title: "abc"))
        await assertThrows { try await self.service().perform(ActionNode(title: "x", kind: .script("../lib/inflection.js")), clipID: id) }
    }

    func testBuiltinsStillWork() async throws {
        let id = try XCTUnwrap(try store.insert(text("abc"), title: "abc"))
        try await service().perform(ActionNode(title: "Plain", kind: .builtin(.pasteAsPlainText)), clipID: id)
        XCTAssertEqual(pastedText(), "abc")
        try await service().perform(ActionNode(title: "Remove", kind: .builtin(.remove)), clipID: id)
        XCTAssertEqual(try store.count(), 0)
    }

    func testPasteAsFilePathGivesPosixAndHFSPaths() async throws {
        let files = [Representation(type: "public.file-url", data: Data("file:///Users/me/a%20b.txt\nfile:///tmp/c.txt".utf8))]
        let id = try XCTUnwrap(try store.insert(files, title: "files"))
        XCTAssertEqual(ClipAction.available(for: files).contains(.pasteAsFilePath), true)
        try await service().perform(ActionNode(title: "Path", kind: .builtin(.pasteAsFilePath)), clipID: id)
        XCTAssertEqual(pastedText(), "/Users/me/a b.txt\n/tmp/c.txt")
        try await service().perform(ActionNode(title: "HFS", kind: .builtin(.pasteAsHFSFilePath)), clipID: id)
        XCTAssertTrue(try XCTUnwrap(pastedText()).contains(":"))
        XCTAssertFalse(try XCTUnwrap(pastedText()).contains("/"))
    }
}
