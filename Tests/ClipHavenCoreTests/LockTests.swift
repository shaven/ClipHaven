import XCTest
@testable import ClipHavenCore

final class LockTests: SecretTestCase {
    func testACancelledAuthenticationPastesNothing() throws {
        let id = try keychainSnippet()
        auth.allow = false
        board.userCopies("prior text")
        board.events = []
        let outcome = try paster().paste(snippetID: id)
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(auth.calls, 1)
        XCTAssertEqual(board.plainText, "prior text")
        XCTAssertEqual(board.events, [])
    }

    func testAFailedAuthenticationNeverReadsTheKeychain() throws {
        final class Spy: SecretProvider {
            var reads = 0
            func read(_ ref: SecretRef) throws -> String? { reads += 1; return "x" }
            func store(_ value: String, as ref: SecretRef) throws {}
            func remove(_ ref: SecretRef) throws {}
        }
        let spy = Spy()
        let id = try keychainSnippet()
        auth.allow = false
        let paster = SecretPaster(snippets: snippets, secrets: spy, authenticator: auth, pasteboard: board,
                                  poster: board, scheduler: scheduler, autoPaste: true, restoreDelay: 2)
        _ = try paster.paste(snippetID: id)
        XCTAssertEqual(spy.reads, 0)
    }

    func testEveryPasteAuthenticatesAgain() throws {
        let id = try keychainSnippet()
        let paster = paster()
        try paster.paste(snippetID: id)
        try paster.paste(snippetID: id)
        XCTAssertEqual(auth.calls, 2)
    }

    func testAFlaggedPlainSnippetNeedsAuthenticationToo() throws {
        let id = try snippets.addSnippet(folderID: folder, title: "flagged", content: "plain but locked")
        try snippets.setRequiresAuth(id: id, true)
        auth.allow = false
        XCTAssertEqual(try paster().paste(snippetID: id), .cancelled)
        XCTAssertEqual(board.events, [])
        auth.allow = true
        XCTAssertEqual(try paster().paste(snippetID: id), .pasted)
        XCTAssertEqual(board.plainText, "plain but locked")
        XCTAssertEqual(auth.calls, 2)
    }

    func testAnUnlockedSnippetIsNotThePasterJob() throws {
        let id = try snippets.addSnippet(folderID: folder, title: "plain", content: "hello")
        XCTAssertEqual(try paster().paste(snippetID: id), .notLocked)
        XCTAssertEqual(auth.calls, 0)
        XCTAssertEqual(board.events, [])
    }

    func testMoveToKeychainStoresTheValueAndLeavesNoPlainText() throws {
        let id = try snippets.addSnippet(folderID: folder, title: "imported", content: fakeSecretValue)
        let ref = SecretRef(service: "ClipHaven", account: "imported")
        try paster().moveToKeychain(snippetID: id, as: ref)
        XCTAssertEqual(secrets.items[ref], fakeSecretValue)
        let snippet = try XCTUnwrap(try snippets.snippet(id: id))
        XCTAssertEqual(snippet.content, "")
        XCTAssertEqual(snippet.secret, ref)
    }

    func testMoveToKeychainKeepsTheTextWhenTheKeychainRefuses() throws {
        let id = try snippets.addSnippet(folderID: folder, title: "imported", content: fakeSecretValue)
        secrets.failStore = true
        XCTAssertThrowsError(try paster().moveToKeychain(snippetID: id, as: SecretRef(service: "ClipHaven", account: "imported")))
        let snippet = try XCTUnwrap(try snippets.snippet(id: id))
        XCTAssertEqual(snippet.content, fakeSecretValue)
        XCTAssertNil(snippet.secret)
    }

    func testMenuSummariesMarkLockedSnippets() throws {
        let locked = try keychainSnippet()
        let plain = try snippets.addSnippet(folderID: folder, title: "plain", content: "hello")
        let summaries = try snippets.menuSummaries().flatMap(\.snippets)
        XCTAssertEqual(summaries.first { $0.id == locked }?.isLocked, true)
        XCTAssertEqual(summaries.first { $0.id == plain }?.isLocked, false)
    }
}

final class DeleteSecretTests: SecretTestCase {
    private let ref = SecretRef(service: "ClipHaven-test", account: "demo")

    func testDeletingWithRemovalDeletesTheKeychainItemAndTheRow() throws {
        let id = try keychainSnippet()
        let removed = try paster().deleteSnippet(id: id, removingKeychainItem: true)
        XCTAssertTrue(removed)
        XCTAssertNil(secrets.items[ref])
        XCTAssertNil(try snippets.snippet(id: id))
    }

    func testDeletingWithoutRemovalLeavesTheKeychainItem() throws {
        let id = try keychainSnippet()
        let removed = try paster().deleteSnippet(id: id, removingKeychainItem: false)
        XCTAssertFalse(removed)
        XCTAssertEqual(secrets.items[ref], fakeSecretValue)
        XCTAssertNil(try snippets.snippet(id: id))
    }

    func testAnItemAnotherSnippetStillUsesIsKept() throws {
        let first = try keychainSnippet()
        let second = try snippets.addSnippet(folderID: folder, title: "same item", content: "")
        try snippets.setSecret(id: second, ref)
        let removed = try paster().deleteSnippet(id: first, removingKeychainItem: true)
        XCTAssertFalse(removed)
        XCTAssertEqual(secrets.items[ref], fakeSecretValue)
        XCTAssertNotNil(try snippets.snippet(id: second))
    }

    func testAPlainSnippetJustDeletes() throws {
        let id = try snippets.addSnippet(folderID: folder, title: "plain", content: "hello")
        XCTAssertFalse(try paster().deleteSnippet(id: id, removingKeychainItem: true))
        XCTAssertNil(try snippets.snippet(id: id))
    }

    func testDeletingAFolderCanRemoveItsKeychainItems() throws {
        try keychainSnippet()
        let removed = try paster().deleteFolder(id: folder, removingKeychainItems: true)
        XCTAssertEqual(removed, 1)
        XCTAssertTrue(secrets.items.isEmpty)
        XCTAssertEqual(try snippets.folderCount(), 0)
    }

    func testKeychainFailureKeepsTheSnippet() throws {
        final class Refusing: SecretProvider {
            func read(_ ref: SecretRef) throws -> String? { "x" }
            func store(_ value: String, as ref: SecretRef) throws {}
            func remove(_ ref: SecretRef) throws { throw SQLiteError(code: 1, message: "refused") }
        }
        let id = try keychainSnippet()
        let paster = SecretPaster(snippets: snippets, secrets: Refusing(), authenticator: auth, pasteboard: board,
                                  poster: board, scheduler: scheduler)
        XCTAssertThrowsError(try paster.deleteSnippet(id: id, removingKeychainItem: true))
        XCTAssertNotNil(try snippets.snippet(id: id))
    }
}
