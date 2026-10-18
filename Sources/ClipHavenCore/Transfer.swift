import CommonCrypto
import CryptoKit
import Foundation

public enum TransferError: Error, CustomStringConvertible {
    case emptyPassphrase
    case notATransferFile
    case wrongPassphraseOrDamaged

    public var description: String {
        switch self {
        case .emptyPassphrase: "a passphrase is needed"
        case .notATransferFile: "not a ClipHaven transfer file"
        case .wrongPassphraseOrDamaged: "wrong passphrase, or the file is damaged"
        }
    }
}

public struct TransferCounts: Equatable, Sendable {
    public let clips: Int
    public let folders: Int
    public let snippets: Int
    /// Passwords written to the Keychain; one the target already had is kept and not counted.
    public let secrets: Int
}

/// Everything ClipHaven keeps, in one file for another Mac: history, snippets, the action list,
/// settings and the password values behind Keychain snippets. The file is sealed with AES-GCM
/// under a key derived from a passphrase (PBKDF2-SHA256), so none of it is readable without it.
public enum Transfer {
    private static let magic = Data("CHTRANSFER1\n".utf8)
    private static let rounds: UInt32 = 600_000

    private struct Payload: Codable {
        struct Secret: Codable {
            var service: String
            var account: String
            var value: String
        }
        var export: Data
        var actions: [ActionNode]?
        var preferences: Data
        var secrets: [Secret]
    }

    public static func seal(history: HistoryStore, snippets: SnippetStore, secrets: SecretProvider, actions: ActionStore,
                            preferences: Preferences, passphrase: String) throws -> Data {
        guard !passphrase.isEmpty else { throw TransferError.emptyPassphrase }
        var seen = Set<SecretRef>()
        var values: [Payload.Secret] = []
        for folder in try snippets.folders() {
            for ref in folder.snippets.compactMap(\.secret) where seen.insert(ref).inserted {
                if let value = try secrets.read(ref) { values.append(.init(service: ref.service, account: ref.account, value: value)) }
            }
        }
        let payload = Payload(export: try Export.data(history: history, snippets: snippets), actions: try actions.load(),
                              preferences: try preferences.exported(), secrets: values)
        let salt = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
        let box = try AES.GCM.seal(try JSONEncoder().encode(payload), using: try key(passphrase, salt: salt))
        return magic + salt + box.combined!
    }

    /// Decrypts and reads the whole file before writing anything, so a wrong passphrase or a
    /// damaged file changes nothing. Clips and snippets are added, not replaced; a password the
    /// target already has is kept; the action list and settings are replaced.
    @discardableResult
    public static func open(_ file: Data, passphrase: String, history: HistoryStore, snippets: SnippetStore,
                            secrets: SecretProvider, actions: ActionStore, preferences: Preferences) throws -> TransferCounts {
        guard file.starts(with: magic), file.count > magic.count + 16 else { throw TransferError.notATransferFile }
        let salt = file.dropFirst(magic.count).prefix(16)
        let sealed = file.dropFirst(magic.count + 16)
        let payload: Payload
        do {
            let plain = try AES.GCM.open(try AES.GCM.SealedBox(combined: sealed), using: try key(passphrase, salt: Data(salt)))
            payload = try JSONDecoder().decode(Payload.self, from: plain)
        } catch {
            throw TransferError.wrongPassphraseOrDamaged
        }

        var stored = 0
        for secret in payload.secrets {
            let ref = SecretRef(service: secret.service, account: secret.account)
            if try secrets.isSynchronized(ref) == nil {
                try secrets.store(secret.value, as: ref)
                stored += 1
            }
        }
        let counts = try Export.restore(payload.export, history: history, snippets: snippets)
        if let tree = payload.actions { try actions.save(tree) }
        try preferences.apply(exported: payload.preferences)
        return TransferCounts(clips: counts.clips, folders: counts.folders, snippets: counts.snippets, secrets: stored)
    }

    private static func key(_ passphrase: String, salt: Data) throws -> SymmetricKey {
        guard !passphrase.isEmpty else { throw TransferError.emptyPassphrase }
        var derived = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { saltBytes in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), passphrase, passphrase.utf8.count,
                                 saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                 CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds, &derived, 32)
        }
        guard status == kCCSuccess else { throw TransferError.wrongPassphraseOrDamaged }
        return SymmetricKey(data: derived)
    }
}
