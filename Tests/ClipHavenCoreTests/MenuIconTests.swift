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

    func testEveryKindButFolderHasItsOwnColourSymbol() {
        let kinds: [MenuIconKind] = [.text, .richText, .pdf, .url, .files, .image, .other, .snippet, .lockedSnippet, .action, .script]
        let symbols = kinds.map { $0.symbol }
        XCTAssertFalse(symbols.contains { $0 == nil || $0!.isEmpty })
        XCTAssertEqual(Set(symbols.compactMap { $0 }).count, kinds.count, "no two kinds share a symbol")
        XCTAssertNil(MenuIconKind.folder.symbol, "folders keep the Finder folder")
    }

    func testTheHistoryTypesAreToldApartByColour() {
        let tints = [MenuIconKind.text, .richText, .pdf, .url, .image].map { $0.tint }
        XCTAssertEqual(Set(tints).count, tints.count)
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
        XCTAssertEqual(StatusIconChoice.colour.file, nil)
        for choice in StatusIconChoice.all where choice.file != nil {
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(choice.file!).path), choice.title)
        }
        XCTAssertEqual(StatusIconChoice.all.filter(\.isColour).map(\.id), ["colour", "diagonal-color", "scissors1-color", "scissors2-color"])
        XCTAssertEqual(StatusIconChoice.default, .colour, "the coloured ClipHaven icon is the default")
        XCTAssertEqual(StatusIconChoice.resolve("nope"), .colour)
        XCTAssertEqual(StatusIconChoice.resolve("template"), .template)
        XCTAssertEqual(StatusIconChoice.resolve(StatusIconChoice.all[2].id), StatusIconChoice.all[2])
        XCTAssertEqual(Set(StatusIconChoice.all.map(\.id)).count, StatusIconChoice.all.count)
    }
}
