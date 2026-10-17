import SQLite3
import XCTest
@testable import ClipHavenCore

final class HistoryStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("HistoryStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeStore(maxCount: Int = 100, maxImageBytes: Int = 1_000_000) throws -> HistoryStore {
        try HistoryStore(url: dir.appendingPathComponent("history.sqlite"),
                         limits: .init(maxCount: maxCount, maxImageBytes: maxImageBytes))
    }

    private func text(_ s: String) -> [Representation] {
        [Representation(type: "public.utf8-plain-text", data: Data(s.utf8))]
    }

    func testFileCopyWithNameTextSummarisesAsFile() throws {
        let store = try makeStore()
        try store.insert(text("report.pptx") + [Representation(type: "public.file-url", data: Data("file:///tmp/report.pptx".utf8))],
                         title: "report.pptx")
        try store.insert(text("plain"), title: "plain")

        let summaries = try store.summaries(limit: 10)
        XCTAssertEqual(summaries.map(\.primaryType), ["public.utf8-plain-text", "public.file-url"])
    }

    func testInsertAndFetchNewestFirst() throws {
        let store = try makeStore()
        try store.insert(text("one"), title: "one")
        try store.insert(text("two"), title: "two")
        try store.insert(text("three"), title: "three")

        let clips = try store.fetch(limit: 10)
        XCTAssertEqual(clips.map(\.title), ["three", "two", "one"])
        XCTAssertEqual(clips.first?.representations, text("three"))
        XCTAssertEqual(try store.count(), 3)
    }

    func testFetchRespectsLimitAndOffset() throws {
        let store = try makeStore()
        for i in 1...30 { try store.insert(text("\(i)"), title: "\(i)") }
        XCTAssertEqual(try store.fetch(limit: 3).map(\.title), ["30", "29", "28"])
        XCTAssertEqual(try store.fetch(limit: 2, offset: 20).map(\.title), ["10", "9"])
    }

    func testKeepsEveryRepresentationOfAClip() throws {
        let store = try makeStore()
        let reps = [
            Representation(type: "public.rtf", data: Data("{\\rtf1 hi}".utf8)),
            Representation(type: "public.utf8-plain-text", data: Data("hi".utf8)),
        ]
        try store.insert(reps, title: "hi")
        XCTAssertEqual(try store.fetch(limit: 1).first?.representations.sorted { $0.type < $1.type }, reps)
    }

    func testDuplicateMovesExistingClipToTop() throws {
        let store = try makeStore()
        let first = try store.insert(text("a"), title: "a")
        try store.insert(text("b"), title: "b")
        let again = try store.insert(text("a"), title: "a")

        XCTAssertEqual(again, first, "a duplicate reuses the existing row")
        XCTAssertEqual(try store.fetch(limit: 10).map(\.title), ["a", "b"])
        XCTAssertEqual(try store.count(), 2)
    }

    func testCountCapDropsOldest() throws {
        let store = try makeStore(maxCount: 5)
        for i in 1...8 { try store.insert(text("\(i)"), title: "\(i)") }
        XCTAssertEqual(try store.count(), 5)
        XCTAssertEqual(try store.fetch(limit: 10).map(\.title), ["8", "7", "6", "5", "4"])
        XCTAssertEqual(try store.representationRowCount(), 5, "dropped clips take their representations with them")
    }

    func testImageOverByteCapIsDroppedButOtherTypesKept() throws {
        let store = try makeStore(maxImageBytes: 100)
        let big = Representation(type: "public.tiff", data: Data(repeating: 7, count: 101))
        let small = Representation(type: "public.utf8-plain-text", data: Data("caption".utf8))
        try store.insert([big, small], title: "pic")
        XCTAssertEqual(try store.fetch(limit: 1).first?.representations, [small])
    }

    func testClipWithOnlyAnOversizeImageIsNotStored() throws {
        let store = try makeStore(maxImageBytes: 100)
        let id = try store.insert([Representation(type: "public.png", data: Data(count: 500))], title: "big")
        XCTAssertNil(id)
        XCTAssertEqual(try store.count(), 0)
    }

    func testImageAtByteCapIsKept() throws {
        let store = try makeStore(maxImageBytes: 100)
        let exact = Representation(type: "public.tiff", data: Data(count: 100))
        try store.insert([exact], title: "pic")
        XCTAssertEqual(try store.fetch(limit: 1).first?.representations, [exact])
    }

    func testDelete() throws {
        let store = try makeStore()
        try store.insert(text("keep"), title: "keep")
        let gone = try XCTUnwrap(store.insert(text("gone"), title: "gone"))
        try store.delete(id: gone)
        XCTAssertEqual(try store.fetch(limit: 10).map(\.title), ["keep"])
        XCTAssertEqual(try store.representationRowCount(), 1)
    }

    func testPersistsAcrossReopen() throws {
        do {
            let store = try makeStore()
            try store.insert(text("saved"), title: "saved")
        }
        XCTAssertEqual(try makeStore().fetch(limit: 1).map(\.title), ["saved"])
    }

    /// Another process briefly holding the file locked at launch must not stop the store opening.
    func testOpensWhileAnotherConnectionHoldsTheLock() throws {
        let path = dir.appendingPathComponent("history.sqlite").path
        var other: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &other), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(other, "BEGIN EXCLUSIVE", nil, nil, nil), SQLITE_OK)
        let holder = other
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            sqlite3_exec(holder, "COMMIT", nil, nil, nil)
            sqlite3_close(holder)
        }
        let store = try makeStore()
        XCTAssertNotNil(try store.insert(text("after lock"), title: "after lock"))
        XCTAssertEqual(try store.journalMode(), "wal")
    }

    func testUsesWALJournal() throws {
        XCTAssertEqual(try makeStore().journalMode(), "wal")
    }

    /// 10,000 inserts must grow the database roughly linearly: no step rewrites the whole history.
    func testTenThousandInsertsGrowLinearly() throws {
        let store = try makeStore(maxCount: 20_000)
        let payload = String(repeating: "x", count: 200)
        var sizes: [Int] = []
        for i in 1...10_000 {
            try store.insert(text("\(i) \(payload)"), title: "\(i)")
            if i % 2_500 == 0 {
                try store.checkpoint()
                sizes.append(try store.fileSize())
            }
        }
        XCTAssertEqual(try store.count(), 10_000)
        // Each quarter adds about the same bytes as the first one.
        let steps = zip(sizes, [0] + sizes).map { $0 - $1 }
        for step in steps.dropFirst() {
            XCTAssertEqual(Double(step), Double(steps[0]), accuracy: Double(steps[0]) * 0.35, "sizes \(sizes)")
        }
        // ~200-byte clips: well under 1 KB a clip on disk, so nothing is stored twice.
        XCTAssertLessThan(sizes.last!, 10_000 * 1_024)
    }
}
