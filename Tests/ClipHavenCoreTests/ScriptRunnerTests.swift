import Foundation
import XCTest
@testable import ClipHavenCore

final class ScriptRunnerTests: XCTestCase {
    /// ClipMenu's own script tree, kept in `Resources/script`.
    static let bundled = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/script")

    private func runner(prompt: @escaping @Sendable (String) -> String? = { _ in nil },
                        activate: @escaping @Sendable () -> Void = {},
                        user: URL? = nil, timeout: TimeInterval = 5) -> ScriptRunner {
        ScriptRunner(libFolders: (user.map { [$0.appendingPathComponent("lib")] } ?? []) + [Self.bundled.appendingPathComponent("lib")],
                     timeout: timeout, prompt: prompt, activate: activate)
    }

    private func action(_ path: String) -> URL {
        Self.bundled.appendingPathComponent("action/\(path)")
    }

    func testReverse() throws {
        XCTAssertEqual(try runner().run(action("Reverse.js"), clipText: "abc"), "cba")
    }

    func testCaseAndTrim() throws {
        XCTAssertEqual(try runner().run(action("Case/UPPERCASE.js"), clipText: "Hello"), "HELLO")
        XCTAssertEqual(try runner().run(action("Case/lowercase.js"), clipText: "Hello"), "hello")
        XCTAssertEqual(try runner().run(action("Trim/Trim.js"), clipText: "  a b \n"), "a b")
        XCTAssertEqual(try runner().run(action("Trim/LTrim.js"), clipText: "  a "), "a ")
        XCTAssertEqual(try runner().run(action("Trim/RTrim.js"), clipText: "  a "), "  a")
    }

    func testCollapseSpaces() throws {
        XCTAssertEqual(try runner().run(action("Collapse Spaces.js"), clipText: "a    b  c"), "a b c")
    }

    func testCrypt() throws {
        XCTAssertEqual(try runner().run(action("Crypt/Encode to Base64.js"), clipText: "hello"), "aGVsbG8=")
        XCTAssertEqual(try runner().run(action("Crypt/Decode from Base64.js"), clipText: "aGVsbG8="), "hello")
        XCTAssertEqual(try runner().run(action("Crypt/Calculate MD5 hash.js"), clipText: "hello"), "5d41402abc4b2a76b9719d911017c592")
        XCTAssertEqual(try runner().run(action("Crypt/Calculate SHA-1 hash.js"), clipText: "hello"), "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d")
    }

    func testSurround() throws {
        XCTAssertEqual(try runner().run(action("Surround with/( ).js"), clipText: "x"), "(x)")
    }

    func testPromptIsAnsweredAndCancelAborts() throws {
        let tags = action("HTML/Surround with Tags....js")
        XCTAssertEqual(try runner(prompt: { _ in "b" }).run(tags, clipText: "x"), "<b>x</b>")
        XCTAssertThrowsError(try runner(prompt: { _ in nil }).run(tags, clipText: "x"))
    }

    func testEveryBundledScriptRuns() throws {
        let files = FileManager.default.enumerator(at: Self.bundled.appendingPathComponent("action"), includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "js" }
        XCTAssertEqual(files.count, 47)
        for file in files {
            XCTAssertNoThrow(try runner(prompt: { _ in "b" }).run(file, clipText: "Hello World 123 <b>x</b>"), file.lastPathComponent)
        }
    }

    func testThrowingScriptIsAnError() throws {
        let dir = try scratch()
        let script = dir.appendingPathComponent("boom.js")
        try "throw new Error('nope'); return clipText;".write(to: script, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try runner().run(script, clipText: "x"))
    }

    func testNonStringResultIsAnError() throws {
        let dir = try scratch()
        let script = dir.appendingPathComponent("none.js")
        try "var x = 1;".write(to: script, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try runner().run(script, clipText: "x"))
    }

    func testSlowScriptTimesOut() throws {
        let dir = try scratch()
        let script = dir.appendingPathComponent("slow.js")
        try "ClipMenu.activate(); return clipText;".write(to: script, atomically: true, encoding: .utf8)
        let slow = runner(activate: { Thread.sleep(forTimeInterval: 1.5) }, timeout: 0.3)
        XCTAssertThrowsError(try slow.run(script, clipText: "x")) { error in
            XCTAssertEqual(error as? ScriptError, .timedOut)
        }
    }

    func testTimeSpentAnsweringAPromptDoesNotCount() throws {
        let tags = action("HTML/Surround with Tags....js")
        let slowAnswer = runner(prompt: { _ in Thread.sleep(forTimeInterval: 0.8); return "b" }, timeout: 0.3)
        XCTAssertEqual(try slowAnswer.run(tags, clipText: "x"), "<b>x</b>")
    }

    func testRunAsyncGivesTheSameResult() async throws {
        let result = try await runner().runAsync(action("Reverse.js"), clipText: "abc")
        XCTAssertEqual(result, "cba")
    }

    func testUserScriptAndUserLibraryShadowBundled() throws {
        let user = try scratch()
        try FileManager.default.createDirectory(at: user.appendingPathComponent("lib"), withIntermediateDirectories: true)
        try "String.prototype.shout = function () { return this + '!'; }; var shouted = true;"
            .write(to: user.appendingPathComponent("lib/mine.js"), atomically: true, encoding: .utf8)
        let script = user.appendingPathComponent("mine-action.js")
        try "ClipMenu.require('mine'); return clipText.shout();".write(to: script, atomically: true, encoding: .utf8)
        XCTAssertEqual(try runner(user: user).run(script, clipText: "hi"), "hi!")

        // A user copy of a library wins over the bundled one.
        try "String.prototype.reverse = function () { return 'user'; };"
            .write(to: user.appendingPathComponent("lib/JS-methods-string.js"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: user.appendingPathComponent("lib/JS-methods"), withIntermediateDirectories: true)
        try "String.prototype.reverse = function () { return 'user'; };"
            .write(to: user.appendingPathComponent("lib/JS-methods/string.js"), atomically: true, encoding: .utf8)
        XCTAssertEqual(try runner(user: user).run(action("Reverse.js"), clipText: "abc"), "user")
    }

    func testMissingLibraryIsAnError() throws {
        let dir = try scratch()
        let script = dir.appendingPathComponent("lib.js")
        try "if (!ClipMenu.require('nothing/here')) { throw new Error('no lib'); } return clipText;"
            .write(to: script, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try runner().run(script, clipText: "x"))
    }

    private func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("scripts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }
}
