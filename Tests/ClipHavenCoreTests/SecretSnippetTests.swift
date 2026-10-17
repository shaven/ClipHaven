import XCTest
@testable import ClipHavenCore

final class SecretSnippetTests: SecretTestCase {
    private let ref = SecretRef(service: "ClipHaven-test", account: "demo")

    func testASecretSnippetStoresOnlyItsServiceAndAccount() throws {
        let id = try keychainSnippet()
        let snippet = try XCTUnwrap(try snippets.snippet(id: id))
        XCTAssertEqual(snippet.secret, ref)
        XCTAssertEqual(snippet.content, "")
    }

    func testResolvingPutsTheValueOnTheClipboardThenPastesOnce() throws {
        let id = try keychainSnippet()
        let outcome = try paster().paste(snippetID: id)
        XCTAssertEqual(outcome, .pasted)
        XCTAssertEqual(board.plainText, fakeSecretValue)
        XCTAssertEqual(board.events, ["write", "cmd-v"])
    }

    func testTheValueIsMarkedConcealedTransientAndOwn() throws {
        let id = try keychainSnippet()
        try paster().paste(snippetID: id)
        let types = Set(board.contents.map(\.type))
        XCTAssertTrue(types.isSuperset(of: ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", ClipboardMonitor.ownMarkerType]))
    }

    func testTheMonitorDoesNotRecordIt() throws {
        let id = try keychainSnippet()
        try paster().paste(snippetID: id)
        // Whatever the monitor sees on the pasteboard must carry a skip marker.
        let types = Set(board.contents.map(\.type))
        XCTAssertFalse(types.isDisjoint(with: ClipboardMonitor.skipMarkers))
    }

    func testThePriorClipboardComesBackAfterTheDelay() throws {
        let id = try keychainSnippet()
        board.userCopies("prior text")
        try paster(delay: 3).paste(snippetID: id)
        XCTAssertEqual(scheduler.delays, [3])
        scheduler.fire()
        XCTAssertEqual(board.plainText, "prior text")
    }

    func testTheRestoreHappensEvenWhenAutoPasteIsOff() throws {
        let id = try keychainSnippet()
        board.userCopies("prior text")
        try paster(autoPaste: false).paste(snippetID: id)
        XCTAssertEqual(board.events.filter { $0 == "cmd-v" }, [])
        XCTAssertEqual(board.plainText, fakeSecretValue)
        scheduler.fire()
        XCTAssertEqual(board.plainText, "prior text")
    }

    func testAnEmptyPriorClipboardIsClearedAgain() throws {
        let id = try keychainSnippet()
        try paster().paste(snippetID: id)
        scheduler.fire()
        XCTAssertTrue(board.contents.isEmpty)
    }

    func testARestoreWritesNothingOverSomethingTheUserCopiedMeanwhile() throws {
        let id = try keychainSnippet()
        board.userCopies("prior text")
        try paster().paste(snippetID: id)
        board.userCopies("copied during the delay")
        scheduler.fire()
        XCTAssertEqual(board.plainText, "copied during the delay")
    }

    func testAMissingKeychainItemPutsNothingOnTheClipboardAndPostsNoCmdV() throws {
        let id = try keychainSnippet(value: nil)
        board.userCopies("prior text")
        board.events = []
        let outcome = try paster().paste(snippetID: id)
        XCTAssertEqual(outcome, .missing)
        XCTAssertEqual(board.plainText, "prior text")
        XCTAssertEqual(board.events, [])
        XCTAssertTrue(scheduler.delays.isEmpty)
    }

    func testAnUnknownSnippetDoesNothing() throws {
        XCTAssertEqual(try paster().paste(snippetID: 999), .notFound)
        XCTAssertEqual(board.events, [])
    }
}
