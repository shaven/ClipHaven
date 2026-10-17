import AppKit
import XCTest
@testable import ClipHavenCore

final class ActionTests: XCTestCase {
    private let plain = Representation(type: "public.utf8-plain-text", data: Data("hello".utf8))
    private var rtf: Representation {
        let data = NSAttributedString(string: "rich hello").rtf(from: NSRange(location: 0, length: 10), documentAttributes: [:])!
        return Representation(type: "public.rtf", data: data)
    }
    private let tiff = Representation(type: "public.tiff", data: Data([0x4D, 0x4D]))

    func testPlainTextKeepsOnlyTheStringOfARichClip() {
        XCTAssertEqual(ClipAction.plainText(of: [rtf, plain]), [plain])
    }

    func testPlainTextFromRTFOnly() {
        XCTAssertEqual(ClipAction.plainText(of: [rtf]),
                       [Representation(type: "public.utf8-plain-text", data: Data("rich hello".utf8))])
    }

    func testPlainTextOfAnImageIsNil() {
        XCTAssertNil(ClipAction.plainText(of: [tiff]))
    }

    func testAvailableActions() {
        XCTAssertEqual(ClipAction.available(for: [rtf, plain]), [.pasteAsPlainText, .remove])
        XCTAssertEqual(ClipAction.available(for: [tiff]), [.remove])
    }
}
