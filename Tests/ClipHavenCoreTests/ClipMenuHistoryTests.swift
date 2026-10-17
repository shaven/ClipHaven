import AppKit
import XCTest
@testable import ClipHavenCore

/// Writes clips the way ClipMenu archived them: a class named `Clip`, keyed by field.
final class LegacyClipFixture: NSObject, NSCoding {
    var string: String?
    var created = Date(timeIntervalSince1970: 1_700_000_000)
    var rtf: Data?
    var rtfd: Data?
    var pdf: Data?
    var filenames: [String]?
    var urls: [String]?
    var image: NSImage?

    init(string: String? = nil) { self.string = string }
    required init?(coder: NSCoder) { nil }

    func encode(with coder: NSCoder) {
        coder.encode(["NSStringPboardType"] as NSArray, forKey: "types")
        coder.encode(created as NSDate, forKey: "createdDate")
        coder.encode(created as NSDate, forKey: "lastUsedDate")
        coder.encode(string as NSString?, forKey: "stringValue")
        coder.encode(rtf as NSData?, forKey: "RTF")
        coder.encode(rtfd as NSData?, forKey: "RTFD")
        coder.encode(pdf as NSData?, forKey: "PDF")
        coder.encode(filenames as NSArray?, forKey: "filenames")
        coder.encode(urls as NSArray?, forKey: "URL")
        coder.encode(image, forKey: "image")
    }

    static func archive(_ clips: [LegacyClipFixture]) throws -> Data {
        NSKeyedArchiver.setClassName("Clip", for: LegacyClipFixture.self)
        return try NSKeyedArchiver.archivedData(withRootObject: clips as NSArray, requiringSecureCoding: false)
    }
}

final class ClipMenuHistoryTests: XCTestCase {
    private var dir: URL!
    private var store: HistoryStore!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ClipMenuHistoryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = try HistoryStore(url: dir.appendingPathComponent("history.sqlite"))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func text(_ s: String) -> Representation {
        Representation(type: "public.utf8-plain-text", data: Data(s.utf8))
    }

    private func image(side: Int) -> NSImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let image = NSImage(size: NSSize(width: side, height: side))
        image.addRepresentation(rep)
        return image
    }

    // MARK: - Reading the archive

    func testEachFieldBecomesItsOwnRepresentation() throws {
        let rich = LegacyClipFixture(string: "rich words")
        rich.rtf = Data("rtf-bytes".utf8); rich.rtfd = Data("rtfd-bytes".utf8); rich.pdf = Data("pdf-bytes".utf8)
        let link = LegacyClipFixture(string: "https://example.com")
        link.urls = ["https://example.com"]
        let files = LegacyClipFixture()
        files.filenames = ["/Users/me/a b.txt", "/tmp/c.txt"]

        let clips = try ClipMenuHistory.parse(LegacyClipFixture.archive([rich, link, files]), maxImageBytes: 10_000_000)
        XCTAssertEqual(clips.count, 3)
        let types = clips.map { Set($0.representations.map(\.type)) }
        XCTAssertEqual(types[0], ["public.utf8-plain-text", "public.rtf", "com.apple.flat-rtfd", "com.adobe.pdf"])
        XCTAssertEqual(types[1], ["public.utf8-plain-text", "public.url"])
        XCTAssertEqual(types[2], ["public.file-url"])
        XCTAssertEqual(clips[0].representations.first { $0.type == "com.apple.flat-rtfd" }?.data, Data("rtfd-bytes".utf8))
        XCTAssertEqual(clips[2].representations[0].data,
                       Data("file:///Users/me/a%20b.txt\nfile:///tmp/c.txt".utf8))
        XCTAssertEqual(clips[0].created, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testAnImageComesOutAsTIFF() throws {
        let clip = LegacyClipFixture()
        clip.image = image(side: 8)
        let out = try ClipMenuHistory.parse(LegacyClipFixture.archive([clip]), maxImageBytes: 10_000_000)
        let rep = try XCTUnwrap(out.first?.representations.first)
        XCTAssertEqual(rep.type, "public.tiff")
        XCTAssertNotNil(NSBitmapImageRep(data: rep.data))
    }

    func testAnOversizeImageIsKeptAsLosslessPNGIfThatFits() throws {
        let clip = LegacyClipFixture()
        clip.image = image(side: 64) // an empty 64x64 bitmap: a TIFF of tens of KB, a PNG of a few
        let tiffSize = try XCTUnwrap(clip.image?.tiffRepresentation).count
        let out = try ClipMenuHistory.parse(LegacyClipFixture.archive([clip]), maxImageBytes: tiffSize - 1)
        let rep = try XCTUnwrap(out.first?.representations.first)
        XCTAssertEqual(rep.type, "public.png")
        XCTAssertLessThanOrEqual(rep.data.count, tiffSize - 1)
    }

    func testAnImageTooBigEvenAsPNGIsLeftOut() throws {
        let clip = LegacyClipFixture()
        clip.image = image(side: 64)
        XCTAssertEqual(try ClipMenuHistory.parse(LegacyClipFixture.archive([clip]), maxImageBytes: 10).count, 0)
    }

    func testAFileThatIsNotAnArchiveThrows() {
        XCTAssertThrowsError(try ClipMenuHistory.parse(Data("not an archive".utf8), maxImageBytes: 1_000))
    }

    // MARK: - Putting it in history

    func testImportedClipsGoBelowTheCurrentOnesInClipMenuOrder() throws {
        try store.insert([text("current newest")], title: "current newest")
        let archive = try LegacyClipFixture.archive([LegacyClipFixture(string: "old 1"), LegacyClipFixture(string: "old 2"),
                                                     LegacyClipFixture(string: "old 3")])
        let file = dir.appendingPathComponent("clips.data")
        try archive.write(to: file)

        let counts = try ClipMenuHistory.importFile(at: file, into: store, limit: nil)
        XCTAssertEqual(counts.imported, 3)
        XCTAssertEqual(try store.summaries(limit: 10).map(\.title), ["current newest", "old 1", "old 2", "old 3"])
    }

    func testTheLimitTakesTheNewestClips() throws {
        let archive = try LegacyClipFixture.archive((1...5).map { LegacyClipFixture(string: "clip \($0)") })
        let file = dir.appendingPathComponent("clips.data")
        try archive.write(to: file)
        let counts = try ClipMenuHistory.importFile(at: file, into: store, limit: 2)
        XCTAssertEqual(counts.imported, 2)
        XCTAssertEqual(try store.summaries(limit: 10).map(\.title), ["clip 1", "clip 2"])
    }

    func testRunningTheImportTwiceAddsNothingTheSecondTime() throws {
        let file = dir.appendingPathComponent("clips.data")
        try LegacyClipFixture.archive([LegacyClipFixture(string: "a"), LegacyClipFixture(string: "b")]).write(to: file)
        _ = try ClipMenuHistory.importFile(at: file, into: store, limit: nil)
        let again = try ClipMenuHistory.importFile(at: file, into: store, limit: nil)
        XCTAssertEqual(again.imported, 0)
        XCTAssertEqual(again.duplicates, 2)
        XCTAssertEqual(try store.count(), 2)
    }

    func testAFullHistoryStopsTheImportAndKeepsTheCurrentClips() throws {
        let small = try HistoryStore(url: dir.appendingPathComponent("small.sqlite"), limits: .init(maxCount: 3))
        try small.insert([text("current")], title: "current")
        let file = dir.appendingPathComponent("clips.data")
        try LegacyClipFixture.archive((1...5).map { LegacyClipFixture(string: "old \($0)") }).write(to: file)
        let counts = try ClipMenuHistory.importFile(at: file, into: small, limit: nil)
        XCTAssertEqual(counts.imported, 2)
        XCTAssertEqual(try small.summaries(limit: 10).map(\.title), ["current", "old 1", "old 2"])
        XCTAssertEqual(counts.stoppedFull, true)
    }

    func testABadFileChangesNothing() throws {
        let file = dir.appendingPathComponent("clips.data")
        try Data("junk".utf8).write(to: file)
        XCTAssertThrowsError(try ClipMenuHistory.importFile(at: file, into: store, limit: nil))
        XCTAssertEqual(try store.count(), 0)
    }
}
