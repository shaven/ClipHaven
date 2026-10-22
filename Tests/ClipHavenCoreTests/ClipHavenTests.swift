import XCTest
@testable import ClipHavenCore

final class ClipHavenTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(ClipHaven.version, "0.18.1")
        XCTAssertEqual(ClipHaven.bundleIdentifier, "com.shavenconsulting.ClipHaven")
    }
}
