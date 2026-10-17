import XCTest
@testable import ClipHavenCore

final class RightClickGestureTests: XCTestCase {
    func testTheDefaultsAreControlForActionsAndShiftControlForThePasteMenu() {
        XCTAssertEqual(RightClickGesture.defaultActions, [.control])
        XCTAssertEqual(RightClickGesture.defaultPaste, [.shift, .control])
        XCTAssertEqual(RightClickGesture.mode(for: [.control], paste: RightClickGesture.defaultPaste, actions: RightClickGesture.defaultActions), .actions)
        XCTAssertEqual(RightClickGesture.mode(for: [.shift, .control], paste: RightClickGesture.defaultPaste, actions: RightClickGesture.defaultActions), .paste)
    }

    func testOnlyAnExactMatchOpensAMenu() {
        let paste: RightClickModifiers = [.shift, .control], actions: RightClickModifiers = [.control]
        XCTAssertNil(RightClickGesture.mode(for: [], paste: paste, actions: actions), "a plain right-click is the app's own")
        XCTAssertNil(RightClickGesture.mode(for: [.option], paste: paste, actions: actions))
        XCTAssertNil(RightClickGesture.mode(for: [.control, .option], paste: paste, actions: actions))
        XCTAssertNil(RightClickGesture.mode(for: [.shift, .control, .command], paste: paste, actions: actions))
    }

    func testRecordedGesturesReplaceTheDefaults() {
        let paste: RightClickModifiers = [.option, .command], actions: RightClickModifiers = [.option]
        XCTAssertEqual(RightClickGesture.mode(for: [.option, .command], paste: paste, actions: actions), .paste)
        XCTAssertEqual(RightClickGesture.mode(for: [.option], paste: paste, actions: actions), .actions)
        XCTAssertNil(RightClickGesture.mode(for: [.control], paste: paste, actions: actions))
    }

    func testIfBothGesturesAreTheSameThePasteMenuWins() {
        XCTAssertEqual(RightClickGesture.mode(for: [.control], paste: [.control], actions: [.control]), .paste)
    }

    func testTheGestureIsDescribedWithTheMacSymbols() {
        XCTAssertEqual(RightClickModifiers([.shift, .control]).symbols, "⌃⇧")
        XCTAssertEqual(RightClickModifiers([.command, .option, .shift, .control]).symbols, "⌃⌥⇧⌘")
        XCTAssertEqual(RightClickModifiers([]).symbols, "")
    }
}
