import XCTest
@testable import ClipHavenCore

/// Synthetic values only; none of these is a real password.
let fakeSecretValue = "synthetic-secret-value"

final class FakeSecrets: SecretProvider {
    var items: [SecretRef: String] = [:]
    var failStore = false

    func read(_ ref: SecretRef) throws -> String? { items[ref] }

    func store(_ value: String, as ref: SecretRef) throws {
        if failStore { throw SQLiteError(code: 1, message: "store failed") }
        items[ref] = value
    }

    func remove(_ ref: SecretRef) throws { items[ref] = nil }
}

final class FakeAuthenticator: Authenticator {
    var allow = true
    var calls = 0

    func authenticate(reason: String) -> Bool {
        calls += 1
        return allow
    }
}

/// A pasteboard and keyboard in one, recording the order of what happens.
final class FakeBoard: SecretPasteboard, PasteKeyPoster {
    var contents: [Representation] = []
    private(set) var changeCount = 0
    var events: [String] = []

    func write(_ representations: [Representation]) {
        contents = representations
        changeCount += 1
        events.append("write")
    }

    func snapshot() -> [Representation] { contents }

    func clear() {
        contents = []
        changeCount += 1
        events.append("clear")
    }

    func postPaste() { events.append("cmd-v") }

    /// Another app copying something.
    func userCopies(_ text: String) {
        contents = [Representation(type: "public.utf8-plain-text", data: Data(text.utf8))]
        changeCount += 1
    }

    var plainText: String? {
        contents.first { $0.type == "public.utf8-plain-text" }.map { String(decoding: $0.data, as: UTF8.self) }
    }
}

final class FakeScheduler: Scheduler {
    private(set) var delays: [TimeInterval] = []
    private var work: [() -> Void] = []

    func after(_ seconds: TimeInterval, _ body: @escaping () -> Void) {
        delays.append(seconds)
        work.append(body)
    }

    func fire() {
        let due = work
        work = []
        due.forEach { $0() }
    }
}

/// A store with one folder, plus the fakes a `SecretPaster` needs.
class SecretTestCase: XCTestCase {
    var dir: URL!
    var snippets: SnippetStore!
    var folder: Int64!
    var secrets: FakeSecrets!
    var auth: FakeAuthenticator!
    var board: FakeBoard!
    var scheduler: FakeScheduler!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("SecretTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        snippets = try SnippetStore(url: dir.appendingPathComponent("history.sqlite"))
        folder = try snippets.addFolder(title: "Logins")
        secrets = FakeSecrets()
        auth = FakeAuthenticator()
        board = FakeBoard()
        scheduler = FakeScheduler()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func paster(autoPaste: Bool = true, delay: TimeInterval = 2) -> SecretPaster {
        SecretPaster(snippets: snippets, secrets: secrets, authenticator: auth, pasteboard: board,
                     poster: board, scheduler: scheduler, autoPaste: autoPaste, restoreDelay: delay)
    }

    @discardableResult
    func keychainSnippet(ref: SecretRef = SecretRef(service: "ClipHaven-test", account: "demo"), value: String? = fakeSecretValue) throws -> Int64 {
        let id = try snippets.addSnippet(folderID: folder, title: "demo login", content: "")
        try snippets.setSecret(id: id, ref)
        if let value { secrets.items[ref] = value }
        return id
    }
}
