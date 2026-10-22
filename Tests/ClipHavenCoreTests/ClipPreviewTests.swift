import XCTest
@testable import ClipHavenCore

final class ClipPreviewTests: XCTestCase {
    private func rep(_ type: String, _ s: String) -> Representation { Representation(type: type, data: Data(s.utf8)) }

    func testShortTextIsShownWhole() {
        XCTAssertEqual(ClipPreview.content(for: [rep("public.utf8-plain-text", "hello")]), .text("hello"))
    }

    func testLongTextIsCutWithEllipsis() {
        let long = String(repeating: "a", count: 1_000)
        XCTAssertEqual(ClipPreview.content(for: [rep("public.utf8-plain-text", long)]),
                       .text(String(repeating: "a", count: ClipPreview.textLimit) + "…"))
    }

    func testManyLinesAreCutToTheLineLimit() {
        let lines = (1...30).map { "line\($0)" }.joined(separator: "\n")
        guard case .text(let shown)? = ClipPreview.content(for: [rep("public.utf8-plain-text", lines)]) else { return XCTFail() }
        XCTAssertEqual(shown, (1...ClipPreview.lineLimit).map { "line\($0)" }.joined(separator: "\n") + "…")
    }

    func testHugeTextOnlyDecodesASlice() {
        let big = Data(repeating: UInt8(ascii: "x"), count: 5_000_000)
        XCTAssertEqual(ClipPreview.excerpt(big).count, ClipPreview.textLimit + 1)
    }

    func testImageClipGivesItsBytes() {
        let png = Representation(type: "public.png", data: Data([1, 2, 3]))
        XCTAssertEqual(ClipPreview.content(for: [png]), .image(Data([1, 2, 3])))
    }

    func testTextBeatsImageWhenBothArePresent() {
        let png = Representation(type: "public.png", data: Data([1]))
        XCTAssertEqual(ClipPreview.content(for: [png, rep("public.utf8-plain-text", "caption")]), .text("caption"))
    }

    func testPDFAndRichText() {
        XCTAssertEqual(ClipPreview.content(for: [Representation(type: "com.adobe.pdf", data: Data([9]))]), .pdf(Data([9])))
        XCTAssertEqual(ClipPreview.content(for: [rep("public.rtf", "{\\rtf1}")]), .rich(Data("{\\rtf1}".utf8), isRTFD: false))
        XCTAssertEqual(ClipPreview.content(for: [Representation(type: "com.apple.flat-rtfd", data: Data([7]))]), .rich(Data([7]), isRTFD: true))
    }

    func testFilenamesClipListsPaths() {
        let files = rep("public.file-url", "file:///tmp/a.txt\nfile:///tmp/b%20c.txt")
        XCTAssertEqual(ClipPreview.content(for: [files]), .files(["/tmp/a.txt", "/tmp/b c.txt"]))
    }

    func testUnknownTypeHasNoPreview() {
        XCTAssertNil(ClipPreview.content(for: [rep("com.example.thing", "x")]))
    }

    func testLockedSnippetsNeverShowTheirContent() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Preview-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SnippetStore(url: dir.appendingPathComponent("s.sqlite"))
        let folder = try store.addFolder(title: "F")
        let plain = try store.addSnippet(folderID: folder, title: "p", content: "visible text")
        let touch = try store.addSnippet(folderID: folder, title: "t", content: "hidden text")
        try store.setRequiresAuth(id: touch, true)
        let keychain = try store.addSnippet(folderID: folder, title: "k", content: "")
        try store.setSecret(id: keychain, SecretRef(service: "svc", account: "acct"))

        XCTAssertEqual(ClipPreview.content(for: try XCTUnwrap(store.snippet(id: plain))), .text("visible text"))
        XCTAssertEqual(ClipPreview.content(for: try XCTUnwrap(store.snippet(id: touch))), .locked("Requires Touch ID"))
        XCTAssertEqual(ClipPreview.content(for: try XCTUnwrap(store.snippet(id: keychain))), .locked("Keychain password"))
    }
}
