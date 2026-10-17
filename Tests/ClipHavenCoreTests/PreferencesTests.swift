import CoreGraphics
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

    func testLookDefaults() {
        let prefs = Preferences(defaults: defaults)
        XCTAssertTrue(prefs.showIcons)
        XCTAssertEqual(prefs.iconSize, 16)
        XCTAssertTrue(prefs.showThumbnails)
        XCTAssertEqual([prefs.thumbnailWidth, prefs.thumbnailHeight], [100, 32])
        XCTAssertEqual(prefs.statusIcon, "colour")
        let look = prefs.appearance
        XCTAssertEqual(look.iconSize, 16)
        XCTAssertEqual(look.thumbnailSize, CGSize(width: 100, height: 32))
        XCTAssertTrue(look.showIcons && look.showThumbnails)
    }

    func testIconSizeSnapsToAMenuSizeAndThumbnailsClamp() {
        var prefs = Preferences(defaults: defaults)
        prefs.iconSize = 20
        XCTAssertEqual(prefs.iconSize, 16)
        prefs.iconSize = 41
        XCTAssertEqual(prefs.iconSize, 48)
        prefs.iconSize = 5
        XCTAssertEqual(prefs.iconSize, 16)
        prefs.thumbnailWidth = 9_999
        prefs.thumbnailHeight = 1
        XCTAssertEqual([prefs.thumbnailWidth, prefs.thumbnailHeight], [256, 16])
    }

    func testResetRestoresTheLook() {
        var prefs = Preferences(defaults: defaults)
        prefs.showIcons = false
        prefs.iconSize = 48
        prefs.statusIcon = "diagonal-color"
        prefs.reset()
        XCTAssertTrue(prefs.showIcons)
        XCTAssertEqual(prefs.iconSize, 16)
        XCTAssertEqual(prefs.statusIcon, "colour")
    }
}

