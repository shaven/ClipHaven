import XCTest
@testable import ClipHavenCore

final class ExportTests: SecretTestCase {
    private var history: HistoryStore!
    private var cleanDir: URL!
    private var cleanHistory: HistoryStore!
    private var cleanSnippets: SnippetStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        history = try HistoryStore(url: dir.appendingPathComponent("history.sqlite"))
        cleanDir = FileManager.default.temporaryDirectory.appendingPathComponent("ExportClean-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: cleanDir, withIntermediateDirectories: true)
        let url = cleanDir.appendingPathComponent("history.sqlite")
        cleanHistory = try HistoryStore(url: url)
        cleanSnippets = try SnippetStore(url: url)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: cleanDir)
        try super.tearDownWithError()
    }

    private func text(_ s: String) -> [Representation] {
        [Representation(type: "public.utf8-plain-text", data: Data(s.utf8))]
    }

    private func fill() throws {
        try history.insert(text("one"), title: "one")
        try history.insert(text("two") + [Representation(type: "public.rtf", data: Data([0, 1, 2, 255]))], title: "two")
        let plain = try snippets.addSnippet(folderID: folder, title: "greeting", content: "Hello,\nthere", enabled: false)
        try snippets.setRequiresAuth(id: plain, true)
        try keychainSnippet()
        let second = try snippets.addFolder(title: "Empty", enabled: false)
        _ = second
    }

    func testRoundTripIntoACleanStoreKeepsCountsOrderAndContent() throws {
        try fill()
        let data = try Export.data(history: history, snippets: snippets)
        let counts = try Export.restore(data, history: cleanHistory, snippets: cleanSnippets)

        XCTAssertEqual(counts, ExportCounts(clips: 2, folders: 2, snippets: 2))
        let clips = try cleanHistory.fetch(limit: 10)
        XCTAssertEqual(clips.map(\.title), ["two", "one"])
        XCTAssertEqual(clips.first?.representations, try history.fetch(limit: 10).first?.representations)

        let folders = try cleanSnippets.folders()
        XCTAssertEqual(folders.map(\.title), ["Logins", "Empty"])
        XCTAssertEqual(folders.map(\.enabled), [true, false])
        let restored = folders[0].snippets
        XCTAssertEqual(restored.map(\.title), ["greeting", "demo login"])
        XCTAssertEqual(restored[0].content, "Hello,\nthere")
        XCTAssertEqual(restored[0].enabled, false)
        XCTAssertEqual(restored[0].requiresAuth, true)
    }

    func testASecretSnippetExportsOnlyItsServiceAndAccount() throws {
        try fill()
        let data = try Export.data(history: history, snippets: snippets)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let folders = try XCTUnwrap(root["folders"] as? [[String: Any]])
        let entries = try XCTUnwrap(folders[0]["snippets"] as? [[String: Any]])
        let secret = try XCTUnwrap(entries.first { $0["title"] as? String == "demo login" })
        XCTAssertEqual(secret["keychain"] as? [String: String], ["service": "ClipHaven-test", "account": "demo"])
        XCTAssertNil(secret["content"])
    }

    func testNoResolvedValueAppearsAnywhereInTheOutput() throws {
        try fill()
        let output = String(decoding: try Export.data(history: history, snippets: snippets), as: UTF8.self)
        XCTAssertFalse(output.contains(fakeSecretValue))
    }

    func testImportedSecretSnippetPointsAtTheSameItemWithNoText() throws {
        try fill()
        _ = try Export.restore(try Export.data(history: history, snippets: snippets), history: cleanHistory, snippets: cleanSnippets)
        let snippet = try XCTUnwrap(try cleanSnippets.folders()[0].snippets.last)
        XCTAssertEqual(snippet.secret, SecretRef(service: "ClipHaven-test", account: "demo"))
        XCTAssertEqual(snippet.content, "")
    }

    func testImportingIntoAStoreThatHasDataAddsAfterIt() throws {
        try fill()
        let data = try Export.data(history: history, snippets: snippets)
        try cleanHistory.insert(text("already here"), title: "already here")
        try cleanSnippets.addFolder(title: "Existing")
        _ = try Export.restore(data, history: cleanHistory, snippets: cleanSnippets)
        XCTAssertEqual(try cleanHistory.fetch(limit: 10).map(\.title), ["two", "one", "already here"])
        XCTAssertEqual(try cleanSnippets.folders().map(\.title), ["Existing", "Logins", "Empty"])
    }

    func testAFileThatIsNotAnExportChangesNothing() throws {
        XCTAssertThrowsError(try Export.restore(Data("not json".utf8), history: cleanHistory, snippets: cleanSnippets))
        let wrongVersion = Data(#"{"version":99,"clips":[],"folders":[]}"#.utf8)
        XCTAssertThrowsError(try Export.restore(wrongVersion, history: cleanHistory, snippets: cleanSnippets))
        XCTAssertEqual(try cleanHistory.count(), 0)
        XCTAssertEqual(try cleanSnippets.folderCount(), 0)
    }

    func testSubfoldersSurviveAnExportAndAnOldFileReadsAsTopLevel() throws {
        let work = try snippets.addFolder(title: "Work")
        let email = try snippets.addFolder(title: "Email", parentID: work)
        try snippets.addSnippet(folderID: email, title: "sig", content: "Regards")
        let data = try Export.data(history: history, snippets: snippets)
        _ = try Export.restore(data, history: cleanHistory, snippets: cleanSnippets)
        let restored = try cleanSnippets.folders()
        let newWork = try XCTUnwrap(restored.first { $0.title == "Work" })
        XCTAssertEqual(restored.first { $0.title == "Email" }?.parentID, newWork.id)
        XCTAssertEqual(restored.first { $0.title == "Email" }?.snippets.map(\.title), ["sig"])

        // A file written before subfolders existed has no "parent" key at all.
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["folders"] = (object["folders"] as? [[String: Any]])?.map { $0.filter { $0.key != "parent" } }
        let old = try JSONSerialization.data(withJSONObject: object)
        let fresh = try SnippetStore(url: cleanDir.appendingPathComponent("old.sqlite"))
        _ = try Export.restore(old, history: try HistoryStore(url: cleanDir.appendingPathComponent("old.sqlite")), snippets: fresh)
        XCTAssertTrue(try fresh.folders().allSatisfy { $0.parentID == nil })
    }
}
