import Foundation
import XCTest
@testable import ClipHavenCore

final class SyncTests: SecretTestCase {
    private func freshStore() throws -> SnippetStore {
        let url = dir.appendingPathComponent("other-\(UUID().uuidString).sqlite")
        return try SnippetStore(url: url)
    }

    private func titles(_ store: SnippetStore) throws -> [String] {
        try store.folders().flatMap { folder in folder.snippets.map { "\(folder.title)/\($0.title)" } }
    }

    // MARK: - Making a password sync

    func testSyncingAPasswordAuthenticatesOnceAndMakesTheItemSynchronizable() throws {
        let ref = SecretRef(service: "ClipHaven-test", account: "demo")
        let id = try keychainSnippet(ref: ref)
        XCTAssertEqual(try paster().synchronize(snippetID: id), .synchronized)
        XCTAssertEqual(auth.calls, 1)
        XCTAssertEqual(secrets.syncCalls, 1)
        XCTAssertEqual(secrets.synced, [ref])
        XCTAssertEqual(secrets.items[ref], fakeSecretValue)
    }

    func testAnAlreadySyncedPasswordIsLeftAloneWithoutAPrompt() throws {
        let ref = SecretRef(service: "ClipHaven-test", account: "demo")
        let id = try keychainSnippet(ref: ref)
        secrets.synced.insert(ref)
        XCTAssertEqual(try paster().synchronize(snippetID: id), .alreadySynchronized)
        XCTAssertEqual(auth.calls, 0)
        XCTAssertEqual(secrets.syncCalls, 0)
    }

    func testACancelledPromptSyncsNothing() throws {
        let id = try keychainSnippet()
        auth.allow = false
        XCTAssertEqual(try paster().synchronize(snippetID: id), .cancelled)
        XCTAssertEqual(secrets.syncCalls, 0)
    }

    func testAMissingItemAndANonKeychainSnippetAreReported() throws {
        let missing = try keychainSnippet(value: nil)
        XCTAssertEqual(try paster().synchronize(snippetID: missing), .missing)
        let plain = try snippets.addSnippet(folderID: folder, title: "plain", content: "hello")
        XCTAssertEqual(try paster().synchronize(snippetID: plain), .notKeychain)
        XCTAssertEqual(try paster().synchronize(snippetID: 9_999), .notFound)
        XCTAssertEqual(secrets.syncCalls, 0)
    }

    func testTheEditorCanAskWhetherAPasswordSyncs() throws {
        let ref = SecretRef(service: "ClipHaven-test", account: "demo")
        let id = try keychainSnippet(ref: ref)
        XCTAssertEqual(try paster().isSynchronized(snippetID: id), false)
        secrets.synced.insert(ref)
        XCTAssertEqual(try paster().isSynchronized(snippetID: id), true)
        let plain = try snippets.addSnippet(folderID: folder, title: "plain", content: "x")
        XCTAssertNil(try paster().isSynchronized(snippetID: plain))
        XCTAssertNil(try paster().isSynchronized(snippetID: try keychainSnippet(ref: SecretRef(service: "a", account: "b"), value: nil)))
    }

    // MARK: - The snapshot

    func testASnapshotHoldsPlainSnippetsAndKeychainReferencesButNoValue() throws {
        _ = try snippets.addSnippet(folderID: folder, title: "greeting", content: "hello there")
        try keychainSnippet()
        let flagged = try snippets.addSnippet(folderID: folder, title: "flagged", content: "sensitive plain text")
        try snippets.setRequiresAuth(id: flagged, true)

        let result = try SnippetSync.snapshot(of: snippets, device: "Mac A")
        let text = String(decoding: result.data, as: UTF8.self)
        XCTAssertTrue(text.contains("hello there"))
        XCTAssertTrue(text.contains("ClipHaven-test"))
        XCTAssertFalse(text.contains(fakeSecretValue))
        XCTAssertFalse(text.contains("sensitive plain text"), "a snippet flagged Require Touch ID is not sent")
        XCTAssertEqual(result.skipped, 1)
    }

    func testMergingIntoAnEmptyStoreRebuildsTheList() throws {
        let plain = try snippets.addSnippet(folderID: folder, title: "greeting", content: "hello there")
        let keychain = try keychainSnippet()
        _ = plain
        let data = try SnippetSync.snapshot(of: snippets, device: "Mac A").data

        let other = try freshStore()
        let counts = try SnippetSync.merge(data, into: other)
        XCTAssertEqual(counts, ImportCounts(folders: 1, snippets: 2))
        XCTAssertEqual(try titles(other), ["Logins/greeting", "Logins/demo login"])
        let copied = try XCTUnwrap(try other.folders().first?.snippets.last)
        XCTAssertEqual(copied.secret, SecretRef(service: "ClipHaven-test", account: "demo"))
        XCTAssertEqual(copied.content, "")
        _ = keychain
    }

    func testMergingTwiceAddsNothingTheSecondTime() throws {
        _ = try snippets.addSnippet(folderID: folder, title: "greeting", content: "hello there")
        let data = try SnippetSync.snapshot(of: snippets, device: "Mac A").data
        let other = try freshStore()
        _ = try SnippetSync.merge(data, into: other)
        XCTAssertEqual(try SnippetSync.merge(data, into: other), ImportCounts(folders: 0, snippets: 0))
        XCTAssertEqual(try titles(other), ["Logins/greeting"])
    }

    func testTheSameTitleWithDifferentTextKeepsBothAndNothingIsReplaced() throws {
        _ = try snippets.addSnippet(folderID: folder, title: "sig", content: "from Mac A")
        let data = try SnippetSync.snapshot(of: snippets, device: "Mac A").data

        let other = try freshStore()
        let otherFolder = try other.addFolder(title: "Logins")
        _ = try other.addSnippet(folderID: otherFolder, title: "sig", content: "from Mac B")
        let counts = try SnippetSync.merge(data, into: other)
        XCTAssertEqual(counts, ImportCounts(folders: 0, snippets: 1))
        XCTAssertEqual(try other.folders().count, 1, "the folder is matched by title")
        XCTAssertEqual(Set(try other.folders()[0].snippets.map(\.content)), ["from Mac A", "from Mac B"])
    }

    func testAFileThatIsNotASnapshotChangesNothing() throws {
        let other = try freshStore()
        XCTAssertThrowsError(try SnippetSync.merge(Data("not json".utf8), into: other))
        XCTAssertEqual(try other.folderCount(), 0)
    }

    func testASnippetFlaggedForTouchIDIsNeverTakenFromAFile() throws {
        let json = """
        {"version":1,"device":"x","updated":"2026-10-17T00:00:00Z","folders":[{"title":"F","enabled":true,"snippets":[
          {"title":"flagged","content":"plain","enabled":true,"requiresAuth":true}]}]}
        """
        let other = try freshStore()
        XCTAssertEqual(try SnippetSync.merge(Data(json.utf8), into: other), ImportCounts(folders: 1, snippets: 0))
    }

    // MARK: - Syncing two Macs through the shared item

    func testTwoMacsConvergeThroughTheSharedSnapshot() throws {
        let shared = FakeSnapshotStore()
        let macB = try freshStore()

        _ = try snippets.addSnippet(folderID: folder, title: "from A", content: "a")
        let first = try SnippetSync.sync(snippets, with: shared, device: "Mac A")
        XCTAssertEqual(first.added, ImportCounts(folders: 0, snippets: 0))
        XCTAssertEqual(first.sent, 1)

        let folderB = try macB.addFolder(title: "Logins")
        _ = try macB.addSnippet(folderID: folderB, title: "from B", content: "b")
        let second = try SnippetSync.sync(macB, with: shared, device: "Mac B")
        XCTAssertEqual(second.added, ImportCounts(folders: 0, snippets: 1))
        XCTAssertEqual(Set(try titles(macB)), ["Logins/from A", "Logins/from B"])

        let third = try SnippetSync.sync(snippets, with: shared, device: "Mac A")
        XCTAssertEqual(third.added, ImportCounts(folders: 0, snippets: 1))
        XCTAssertEqual(Set(try titles(snippets)), ["Logins/from A", "Logins/from B"])
    }

    func testAnUnreadableSharedSnapshotIsNotOverwritten() throws {
        let shared = FakeSnapshotStore()
        shared.data = Data("garbage".utf8)
        XCTAssertThrowsError(try SnippetSync.sync(snippets, with: shared, device: "Mac A"))
        XCTAssertEqual(shared.data, Data("garbage".utf8))
        XCTAssertEqual(shared.writes, 0)
    }
}
