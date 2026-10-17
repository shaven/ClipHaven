import XCTest
@testable import ClipHavenCore

final class ClipHavenTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(ClipHaven.version, "0.1.0")
        XCTAssertEqual(ClipHaven.bundleIdentifier, "com.shavenconsulting.ClipHaven")
    }
}
