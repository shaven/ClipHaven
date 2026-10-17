import Foundation

/// Where a secret lives in the Keychain. This, never the value, is what a snippet stores.
public struct SecretRef: Hashable, Sendable {
    public let service: String
    public let account: String

    public init(service: String, account: String) {
        self.service = service
        self.account = account
    }
}

/// The Keychain, as far as ClipHaven needs it; `KeychainProvider` in the app, a dictionary in tests.
public protocol SecretProvider: AnyObject {
    func read(_ ref: SecretRef) throws -> String?
    func store(_ value: String, as ref: SecretRef) throws
    func remove(_ ref: SecretRef) throws
    /// Whether the item syncs through iCloud Keychain; nil when there is no such item.
    func isSynchronized(_ ref: SecretRef) throws -> Bool?
    /// Makes the item sync through iCloud Keychain, keeping its value. False if there is no item.
    func makeSynchronized(_ ref: SecretRef) throws -> Bool
}

/// Touch ID, else the Mac password. Asked afresh on every locked paste.
public protocol Authenticator: AnyObject {
    func authenticate(reason: String) -> Bool
}

/// The pasteboard as the secret paste needs it: write, look at, and put back.
public protocol SecretPasteboard: PasteboardWriter {
    var changeCount: Int { get }
    func snapshot() -> [Representation]
    func clear()
}

/// Runs `work` once after a delay; a main-queue timer in the app, a manual trigger in tests.
public protocol Scheduler {
    func after(_ seconds: TimeInterval, _ work: @escaping () -> Void)
}

public enum SecretSyncOutcome: Equatable, Sendable {
    case synchronized
    case alreadySynchronized
    /// Authentication failed or was cancelled: nothing was changed.
    case cancelled
    case missing
    /// Not a Keychain snippet, so there is no item to sync.
    case notKeychain
    case notFound
}

public enum SecretPasteOutcome: Equatable, Sendable {
    case pasted
    /// Authentication failed or was cancelled: nothing was read or written.
    case cancelled
    /// The Keychain has no such item.
    case missing
    /// Not a locked snippet; the ordinary snippet paste handles it.
    case notLocked
    case notFound
}

/// Pastes a locked snippet (a Keychain snippet, or one flagged "Require Touch ID"). The value goes
/// on the pasteboard marked Concealed and Transient, so no clipboard manager keeps it, is pasted
/// when auto-paste is on, and the clipboard it replaced is put back after `restoreDelay`.
public final class SecretPaster {
    public static let concealedType = "org.nspasteboard.ConcealedType"
    public static let transientType = "org.nspasteboard.TransientType"

    public var autoPaste: Bool
    public var restoreDelay: TimeInterval
    private let snippets: SnippetStore
    private let secrets: SecretProvider
    private let authenticator: Authenticator
    private let pasteboard: SecretPasteboard
    private let poster: PasteKeyPoster
    private let scheduler: Scheduler

    public init(snippets: SnippetStore, secrets: SecretProvider, authenticator: Authenticator,
                pasteboard: SecretPasteboard, poster: PasteKeyPoster, scheduler: Scheduler,
                autoPaste: Bool = true, restoreDelay: TimeInterval = 2) {
        self.snippets = snippets
        self.secrets = secrets
        self.authenticator = authenticator
        self.pasteboard = pasteboard
        self.poster = poster
        self.scheduler = scheduler
        self.autoPaste = autoPaste
        self.restoreDelay = restoreDelay
    }

    public func paste(snippetID: Int64) throws -> SecretPasteOutcome {
        guard let snippet = try snippets.snippet(id: snippetID) else { return .notFound }
        guard snippet.isLocked else { return .notLocked }
        // Every paste asks again; nothing is cached between pastes.
        guard authenticator.authenticate(reason: "paste “\(snippet.title)”") else { return .cancelled }

        let value: String
        if let ref = snippet.secret {
            guard let found = try secrets.read(ref) else { return .missing }
            value = found
        } else {
            value = snippet.content
        }

        let prior = pasteboard.snapshot()
        pasteboard.write([
            Representation(type: ClipType.string.pasteboardType, data: Data(value.utf8)),
            Representation(type: Self.concealedType, data: Data()),
            Representation(type: Self.transientType, data: Data()),
            Representation(type: ClipboardMonitor.ownMarkerType, data: Data()),
        ])
        let ours = pasteboard.changeCount
        if autoPaste { poster.postPaste() }

        scheduler.after(restoreDelay) { [pasteboard] in
            // Someone copied in the meantime: leave their clipboard alone.
            guard pasteboard.changeCount == ours else { return }
            if prior.isEmpty {
                pasteboard.clear()
            } else {
                pasteboard.write(prior)
            }
        }
        return .pasted
    }

    /// Whether a Keychain snippet's item syncs through iCloud Keychain; nil for any other snippet
    /// or an item that is not there.
    public func isSynchronized(snippetID: Int64) throws -> Bool? {
        guard let ref = try snippets.snippet(id: snippetID)?.secret else { return nil }
        return try secrets.isSynchronized(ref)
    }

    /// Makes a Keychain snippet's item sync through iCloud Keychain, so the other Macs on the same
    /// Apple ID get it. Reading the value is the sensitive step, so it asks for Touch ID first.
    public func synchronize(snippetID: Int64) throws -> SecretSyncOutcome {
        guard let snippet = try snippets.snippet(id: snippetID) else { return .notFound }
        guard let ref = snippet.secret else { return .notKeychain }
        switch try secrets.isSynchronized(ref) {
        case nil: return .missing
        case true?: return .alreadySynchronized
        case false?: break
        }
        guard authenticator.authenticate(reason: "sync “\(snippet.title)” through iCloud Keychain") else { return .cancelled }
        return try secrets.makeSynchronized(ref) ? .synchronized : .missing
    }

    /// Deletes a snippet, and with `removingKeychainItem` its Keychain item too, unless another
    /// snippet still points at that item. Returns whether an item was removed. The item goes
    /// first, so a Keychain failure leaves the snippet in place.
    @discardableResult
    public func deleteSnippet(id: Int64, removingKeychainItem: Bool) throws -> Bool {
        guard let snippet = try snippets.snippet(id: id) else { return false }
        var removed = false
        if removingKeychainItem, let ref = snippet.secret, try snippets.secretReferenceCount(ref) == 1 {
            try secrets.remove(ref)
            removed = true
        }
        try snippets.deleteSnippet(id: id)
        return removed
    }

    /// Deletes a folder and its snippets; returns how many Keychain items were removed.
    @discardableResult
    public func deleteFolder(id: Int64, removingKeychainItems: Bool) throws -> Int {
        var removed = 0
        if removingKeychainItems, let folder = try snippets.folders().first(where: { $0.id == id }) {
            for snippet in folder.snippets where snippet.secret != nil {
                if try deleteSnippet(id: snippet.id, removingKeychainItem: true) { removed += 1 }
            }
        }
        try snippets.deleteFolder(id: id)
        return removed
    }

    /// Stores the snippet's text in the Keychain under `ref`, then removes it from the snippet
    /// store. The Keychain write comes first: if it fails the text is still where it was.
    public func moveToKeychain(snippetID: Int64, as ref: SecretRef) throws {
        guard let snippet = try snippets.snippet(id: snippetID) else { return }
        try secrets.store(snippet.content, as: ref)
        try snippets.setSecret(id: snippetID, ref)
    }
}
