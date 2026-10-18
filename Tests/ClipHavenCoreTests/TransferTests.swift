import XCTest
@testable import ClipHavenCore

@MainActor
final class TransferTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("TransferTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func machine(_ name: String) throws -> (history: HistoryStore, snippets: SnippetStore, secrets: FakeSecrets, actions: ActionStore, prefs: Preferences) {
        let url = dir.appendingPathComponent("\(name).sqlite")
        let suite = UserDefaults(suiteName: "TransferTests-\(name)-\(UUID().uuidString)")!
        return (try HistoryStore(url: url), try SnippetStore(url: url), FakeSecrets(),
                ActionStore(url: dir.appendingPathComponent("\(name)-actions.json")), Preferences(defaults: suite))
    }

    private func fill(_ m: (history: HistoryStore, snippets: SnippetStore, secrets: FakeSecrets, actions: ActionStore, prefs: Preferences)) throws {
        _ = try m.history.insert([Representation(type: "public.utf8-plain-text", data: Data("hello".utf8))], title: "hello", created: Date())
        let ref = SecretRef(service: "svc", account: "me")
        _ = try m.snippets.importFolders([ImportedFolder(title: "F", enabled: true, snippets: [
            ImportedSnippet(title: "plain", content: "text", enabled: true),
            ImportedSnippet(title: "pw", content: "", enabled: true, secret: ref, requiresAuth: true)])])
        m.secrets.items[ref] = fakeSecretValue
        try m.actions.save([ActionNode(title: "Plain", kind: .builtin(.pasteAsPlainText))])
        var prefs = m.prefs
        prefs.maxCount = 2_000
        prefs.autoPaste = false
    }

    func testRoundTripMovesEverythingToAnotherMachine() throws {
        let a = try machine("a"), b = try machine("b")
        try fill(a)
        let file = try Transfer.seal(history: a.history, snippets: a.snippets, secrets: a.secrets, actions: a.actions,
                                     preferences: a.prefs, passphrase: "correct horse")
        let counts = try Transfer.open(file, passphrase: "correct horse", history: b.history, snippets: b.snippets,
                                       secrets: b.secrets, actions: b.actions, preferences: b.prefs)
        XCTAssertEqual(counts.clips, 1)
        XCTAssertEqual(counts.snippets, 2)
        XCTAssertEqual(counts.secrets, 1)
        XCTAssertEqual(b.secrets.items[SecretRef(service: "svc", account: "me")], fakeSecretValue)
        XCTAssertEqual(try b.actions.load()?.first?.title, "Plain")
        XCTAssertEqual(b.prefs.maxCount, 2_000)
        XCTAssertFalse(b.prefs.autoPaste)
    }

    func testFileHoldsNoPlainText() throws {
        let a = try machine("a")
        try fill(a)
        let file = try Transfer.seal(history: a.history, snippets: a.snippets, secrets: a.secrets, actions: a.actions,
                                     preferences: a.prefs, passphrase: "pass")
        let text = String(decoding: file, as: UTF8.self)
        XCTAssertFalse(text.contains(fakeSecretValue))
        XCTAssertFalse(text.contains("hello"))
    }

    func testWrongPassphraseChangesNothing() throws {
        let a = try machine("a"), b = try machine("b")
        try fill(a)
        let file = try Transfer.seal(history: a.history, snippets: a.snippets, secrets: a.secrets, actions: a.actions,
                                     preferences: a.prefs, passphrase: "right")
        XCTAssertThrowsError(try Transfer.open(file, passphrase: "wrong", history: b.history, snippets: b.snippets,
                                               secrets: b.secrets, actions: b.actions, preferences: b.prefs)) {
            guard case TransferError.wrongPassphraseOrDamaged = $0 else { return XCTFail("\($0)") }
        }
        XCTAssertEqual(try b.history.count(), 0)
        XCTAssertTrue(b.secrets.items.isEmpty)
        XCTAssertNil(try b.actions.load())
    }

    func testNotATransferFile() throws {
        let b = try machine("b")
        XCTAssertThrowsError(try Transfer.open(Data("{}".utf8), passphrase: "x", history: b.history, snippets: b.snippets,
                                               secrets: b.secrets, actions: b.actions, preferences: b.prefs)) {
            guard case TransferError.notATransferFile = $0 else { return XCTFail("\($0)") }
        }
    }

    func testEmptyPassphraseRefused() throws {
        let a = try machine("a")
        XCTAssertThrowsError(try Transfer.seal(history: a.history, snippets: a.snippets, secrets: a.secrets,
                                               actions: a.actions, preferences: a.prefs, passphrase: ""))
    }

    func testExistingSecretOnTargetIsKept() throws {
        let a = try machine("a"), b = try machine("b")
        try fill(a)
        let ref = SecretRef(service: "svc", account: "me")
        b.secrets.items[ref] = "already-here"
        let file = try Transfer.seal(history: a.history, snippets: a.snippets, secrets: a.secrets, actions: a.actions,
                                     preferences: a.prefs, passphrase: "p")
        let counts = try Transfer.open(file, passphrase: "p", history: b.history, snippets: b.snippets,
                                       secrets: b.secrets, actions: b.actions, preferences: b.prefs)
        XCTAssertEqual(b.secrets.items[ref], "already-here")
        XCTAssertEqual(counts.secrets, 0)
    }

    func testSubfoldersMoveToAnotherMachine() throws {
        let a = try machine("a"), b = try machine("b")
        let work = try a.snippets.addFolder(title: "Work")
        let email = try a.snippets.addFolder(title: "Email", parentID: work)
        try a.snippets.addSnippet(folderID: email, title: "sig", content: "Regards")
        let file = try Transfer.seal(history: a.history, snippets: a.snippets, secrets: a.secrets, actions: a.actions,
                                     preferences: a.prefs, passphrase: "pw")
        _ = try Transfer.open(file, passphrase: "pw", history: b.history, snippets: b.snippets,
                              secrets: b.secrets, actions: b.actions, preferences: b.prefs)
        let folders = try b.snippets.folders()
        XCTAssertEqual(folders.first { $0.title == "Email" }?.parentID, folders.first { $0.title == "Work" }?.id)
    }
}
