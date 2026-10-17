import XCTest
@testable import ClipHavenCore

final class PreferencesTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "PreferencesTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testDefaultsAreClipMenusOwn() {
        let prefs = Preferences(defaults: defaults)
        XCTAssertTrue(prefs.autoPaste)
        XCTAssertEqual(prefs.hotKeyCode, 9)          // V
        XCTAssertEqual(prefs.hotKeyModifiers, 4352)  // Cmd+Ctrl
        XCTAssertFalse(prefs.hasCustomHotKey)
        XCTAssertEqual(prefs.maxCount, 1_000)
        XCTAssertEqual(prefs.maxImageBytes, 10_000_000)
        XCTAssertEqual(prefs.inlineCount, 20)
        XCTAssertEqual(prefs.folderSize, 25)
        XCTAssertEqual(prefs.titleLength, 20)
        XCTAssertTrue(prefs.numbered)
        XCTAssertEqual(prefs.restoreDelay, 2)
    }

    func testTheDefaultsFeedTheMenuLayoutAndTheHistoryLimits() {
        let prefs = Preferences(defaults: defaults)
        let layout = prefs.layout
        XCTAssertEqual([layout.inlineCount, layout.folderSize, layout.titleLength], [20, 25, 20])
        XCTAssertTrue(layout.numbered)
        XCTAssertEqual(prefs.limits.maxCount, 1_000)
        XCTAssertEqual(prefs.limits.maxImageBytes, 10_000_000)
    }

    func testChangesSurviveANewInstance() {
        var prefs = Preferences(defaults: defaults)
        prefs.autoPaste = false
        prefs.inlineCount = 10
        prefs.restoreDelay = 5
        prefs.hotKeyCode = 8
        prefs.hotKeyModifiers = 2304
        let again = Preferences(defaults: defaults)
        XCTAssertFalse(again.autoPaste)
        XCTAssertEqual(again.inlineCount, 10)
        XCTAssertEqual(again.restoreDelay, 5)
        XCTAssertEqual([again.hotKeyCode, again.hotKeyModifiers], [8, 2304])
        XCTAssertTrue(again.hasCustomHotKey)
    }

    func testOutOfRangeValuesAreClamped() {
        var prefs = Preferences(defaults: defaults)
        prefs.folderSize = 0
        prefs.inlineCount = -4
        prefs.restoreDelay = 900
        prefs.maxCount = 1
        XCTAssertEqual(prefs.folderSize, 1)
        XCTAssertEqual(prefs.inlineCount, 0)
        XCTAssertEqual(prefs.restoreDelay, 30)
        XCTAssertEqual(prefs.maxCount, 10)
    }

    func testResetReturnsEveryValueToItsDefault() {
        var prefs = Preferences(defaults: defaults)
        prefs.autoPaste = false
        prefs.hotKeyCode = 8
        prefs.titleLength = 50
        prefs.reset()
        XCTAssertTrue(prefs.autoPaste)
        XCTAssertEqual(prefs.hotKeyCode, 9)
        XCTAssertEqual(prefs.titleLength, 20)
        XCTAssertFalse(prefs.hasCustomHotKey)
    }
}
