import XCTest
@testable import ClipHavenCore

/// Records what reached the pasteboard and the keyboard, in order.
final class PasteLog: PasteboardWriter, PasteKeyPoster {
    var events: [String] = []
    var written: [[Representation]] = []

    func write(_ representations: [Representation]) {
        written.append(representations)
        events.append("write")
    }

    func postPaste() {
        events.append("cmd-v")
    }
}

final class AutoPasteTests: XCTestCase {
    private var dir: URL!
    private var store: HistoryStore!
    private var log: PasteLog!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("AutoPasteTests-\(UUID().uuidString)")
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

    private func paster(autoPaste: Bool = true) -> Paster {
        Paster(store: store, writer: log, poster: log, autoPaste: autoPaste)
    }

    func testChoosingSetsTheClipboardThenPostsCmdVOnce() throws {
        let id = try XCTUnwrap(try store.insert(text("one"), title: "one"))
        try paster().choose(clipID: id)
        XCTAssertEqual(log.events, ["write", "cmd-v"])
        XCTAssertEqual(log.written.first?.filter { $0.type != ClipboardMonitor.ownMarkerType }, text("one"))
    }

    func testWritesCarryTheOwnMarkerSoTheyAreNotRecaptured() throws {
        let id = try XCTUnwrap(try store.insert(text("one"), title: "one"))
        try paster().choose(clipID: id)
        XCTAssertTrue(log.written.first?.contains { $0.type == ClipboardMonitor.ownMarkerType } ?? false)
    }

    func testNoCmdVWhenAutoPasteIsOff() throws {
        let id = try XCTUnwrap(try store.insert(text("one"), title: "one"))
        try paster(autoPaste: false).choose(clipID: id)
        XCTAssertEqual(log.events, ["write"])
    }

    func testChoosingMovesTheClipToTheTop() throws {
        let first = try XCTUnwrap(try store.insert(text("one"), title: "one"))
        try store.insert(text("two"), title: "two")
        try paster().choose(clipID: first)
        XCTAssertEqual(try store.summaries(limit: 10).map(\.title), ["one", "two"])
    }

    func testUnknownClipDoesNothing() throws {
        try paster().choose(clipID: 999)
        XCTAssertEqual(log.events, [])
    }

    func testPasteAsPlainTextWritesOnlyTheString() throws {
        let rich = text("one") + [Representation(type: "public.rtf", data: Data("{\\rtf1 one}".utf8))]
        let id = try XCTUnwrap(try store.insert(rich, title: "one"))
        try paster().perform(.pasteAsPlainText, clipID: id)
        XCTAssertEqual(log.events, ["write", "cmd-v"])
        XCTAssertEqual(log.written.first?.filter { $0.type != ClipboardMonitor.ownMarkerType }, text("one"))
    }

    func testRemoveDeletesAndPastesNothing() throws {
        let id = try XCTUnwrap(try store.insert(text("one"), title: "one"))
        try paster().perform(.remove, clipID: id)
        XCTAssertEqual(try store.count(), 0)
        XCTAssertEqual(log.events, [])
    }

    func testClearEmptiesHistory() throws {
        try store.insert(text("one"), title: "one")
        try store.insert(text("two"), title: "two")
        try store.clear()
        XCTAssertEqual(try store.count(), 0)
    }
}
