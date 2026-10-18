import XCTest
@testable import ClipHavenCore

/// Parses a synthetic Core Data XML store shaped like ClipMenu's `Snippets.xml`; the real file
/// is never read by tests.
final class ClipMenuImportTests: XCTestCase {
    private func fixture() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "snippets-synthetic", withExtension: "xml", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    func testParsesFoldersInIndexOrderEvenWhenTheFileIsOutOfOrder() throws {
        let folders = try ClipMenuImport.parse(fixture())
        XCTAssertEqual(folders.map(\.title), ["Greetings", "Second folder"])
        XCTAssertEqual(folders.map(\.enabled), [true, false])
    }

    func testSnippetsFollowTheirIndexWithinAFolder() throws {
        let greetings = try XCTUnwrap(ClipMenuImport.parse(fixture()).first)
        XCTAssertEqual(greetings.snippets.map(\.title), ["First greeting", "Second greeting"])
    }

    func testContentKeepsEntitiesAndNewlines() throws {
        let greetings = try XCTUnwrap(ClipMenuImport.parse(fixture()).first)
        XCTAssertEqual(greetings.snippets.map(\.content), ["Hello <world>", "Hi & welcome\nline two"])
    }

    func testDisabledSnippetIsKeptAndFlagged() throws {
        let second = try XCTUnwrap(ClipMenuImport.parse(fixture()).last)
        XCTAssertEqual(second.snippets, [ImportedSnippet(title: "Disabled one", content: "off", enabled: false)])
    }

    func testRejectsXMLThatIsNotAClipMenuStore() {
        XCTAssertThrowsError(try ClipMenuImport.parse(Data("<folders/>".utf8)))
        XCTAssertThrowsError(try ClipMenuImport.parse(Data("not xml".utf8)))
    }

    func testImportFileBacksUpTheSourceThenImports() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ImportFile-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = dir.appendingPathComponent("Snippets.xml")
        try fixture().write(to: source)
        let store = try SnippetStore(url: dir.appendingPathComponent("history.sqlite"))

        let result = try ClipMenuImport.importFile(at: source, into: store, backupDirectory: dir.appendingPathComponent("backups"),
                                                   date: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(result.counts, ImportCounts(folders: 2, snippets: 3))
        XCTAssertEqual(try Data(contentsOf: result.backup), try fixture())
        XCTAssertEqual(result.backup.lastPathComponent, "Snippets-1970-01-01T000000Z.xml")
        XCTAssertEqual(try store.folders().count, 2)
    }

    func testImportFileLeavesTheStoreAloneWhenTheFileIsNotAStore() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ImportBad-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = dir.appendingPathComponent("Snippets.xml")
        try Data("<folders/>".utf8).write(to: source)
        let store = try SnippetStore(url: dir.appendingPathComponent("history.sqlite"))

        XCTAssertThrowsError(try ClipMenuImport.importFile(at: source, into: store, backupDirectory: dir.appendingPathComponent("backups")))
        XCTAssertEqual(try store.folderCount(), 0)
    }

    func testClipMenuFoldersImportFlatAndLeaveExistingSubfoldersAlone() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ImportNested-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = try SnippetStore(url: dir.appendingPathComponent("history.sqlite"))
        let work = try store.addFolder(title: "Work")
        try store.addFolder(title: "Email", parentID: work)

        try store.importFolders(ClipMenuImport.parse(fixture()))

        let folders = try store.folders()
        XCTAssertEqual(folders.map(\.title), ["Work", "Email", "Greetings", "Second folder"])
        XCTAssertEqual(folders.map(\.parentID), [nil, work, nil, nil])
    }
}
