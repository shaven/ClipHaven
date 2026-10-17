import CoreGraphics
import XCTest
@testable import ClipHavenCore

final class MenuIconTests: XCTestCase {
    func testEachClipTypeGetsItsKind() {
        XCTAssertEqual(MenuIconKind.kind(forClipType: "public.utf8-plain-text"), .text)
        XCTAssertEqual(MenuIconKind.kind(forClipType: "public.rtf"), .richText)
        XCTAssertEqual(MenuIconKind.kind(forClipType: "com.apple.flat-rtfd"), .richText)
        XCTAssertEqual(MenuIconKind.kind(forClipType: "com.adobe.pdf"), .pdf)
        XCTAssertEqual(MenuIconKind.kind(forClipType: "public.url"), .url)
        XCTAssertEqual(MenuIconKind.kind(forClipType: "public.file-url"), .files)
        for image in ["public.tiff", "public.png", "com.apple.pict"] {
            XCTAssertEqual(MenuIconKind.kind(forClipType: image), .image)
        }
        XCTAssertEqual(MenuIconKind.kind(forClipType: "com.example.unknown"), .other)
    }

    func testAThumbnailFitsTheBoxAndKeepsItsShape() {
        let box = CGSize(width: 100, height: 32)
        XCTAssertEqual(Thumbnail.size(for: CGSize(width: 400, height: 200), within: box), CGSize(width: 64, height: 32))
        XCTAssertEqual(Thumbnail.size(for: CGSize(width: 200, height: 1000), within: box), CGSize(width: 6.4, height: 32))
    }

    func testAThumbnailIsNeverEnlarged() {
        XCTAssertEqual(Thumbnail.size(for: CGSize(width: 20, height: 10), within: CGSize(width: 100, height: 32)),
                       CGSize(width: 20, height: 10))
    }

    func testAnEmptyImageHasNoThumbnail() {
        XCTAssertEqual(Thumbnail.size(for: .zero, within: CGSize(width: 100, height: 32)), .zero)
    }

    func testStatusIconChoicesAllShipAFileAndUnknownNamesFallBack() {
        let folder = ScriptRunnerTests.bundled.deletingLastPathComponent().appendingPathComponent("StatusIcons")
        XCTAssertEqual(StatusIconChoice.template.file, nil)
        for choice in StatusIconChoice.all where choice.file != nil {
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(choice.file!).path), choice.title)
        }
        XCTAssertEqual(StatusIconChoice.all.filter(\.isColour).map(\.id), ["diagonal-color", "scissors1-color", "scissors2-color"])
        XCTAssertEqual(StatusIconChoice.resolve("nope"), .template)
        XCTAssertEqual(StatusIconChoice.resolve(StatusIconChoice.all[1].id), StatusIconChoice.all[1])
        XCTAssertEqual(Set(StatusIconChoice.all.map(\.id)).count, StatusIconChoice.all.count)
    }
}
