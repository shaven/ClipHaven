import Foundation
import JavaScriptCore

public enum ScriptError: Error, Equatable, CustomStringConvertible {
    case unreadable(String)
    case failed(String)
    case noResult
    case timedOut

    public var description: String {
        switch self {
        case .unreadable(let name): "Could not read the script \(name)"
        case .failed(let message): message
        case .noResult: "The script did not return text"
        case .timedOut: "The script took too long"
        }
    }
}

/// Runs ClipMenu's JavaScript actions. A script is the body of a function: it reads `clipText`
/// and `return`s the new text. It can call `ClipMenu.require('lib/name')` to load a helper
/// library, `ClipMenu.activate()` to bring the app forward before asking, and `prompt(text)`.
/// Library folders are searched in order, so the owner's folder can shadow a bundled library.
public struct ScriptRunner: Sendable {
    public let libFolders: [URL]
    public let timeout: TimeInterval
    private let prompt: @Sendable (String) -> String?
    private let activate: @Sendable () -> Void

    public init(libFolders: [URL], timeout: TimeInterval = 5,
                prompt: @escaping @Sendable (String) -> String? = { _ in nil },
                activate: @escaping @Sendable () -> Void = {}) {
        self.libFolders = libFolders
        self.timeout = timeout
        self.prompt = prompt
        self.activate = activate
    }

    /// Runs the script file. JavaScriptCore has no public way to stop a script, so one that
    /// runs past `timeout` is abandoned on its own thread and the caller gets `.timedOut`.
    public func run(_ script: URL, clipText: String) throws -> String {
        guard let source = try? String(contentsOf: script, encoding: .utf8) else {
            throw ScriptError.unreadable(script.lastPathComponent)
        }
        let box = Outcome()
        let done = DispatchSemaphore(value: 0)
        let folders = libFolders, prompt = prompt, activate = activate
        let thread = Thread {
            box.set(Self.evaluate(source, clipText: clipText, libFolders: folders, prompt: prompt, activate: activate))
            done.signal()
        }
        thread.stackSize = 8 << 20
        thread.start()
        guard done.wait(timeout: .now() + timeout) == .success else { throw ScriptError.timedOut }
        return try box.get()
    }

    private static func evaluate(_ source: String, clipText: String, libFolders: [URL],
                                 prompt: @escaping @Sendable (String) -> String?,
                                 activate: @escaping @Sendable () -> Void) -> Result<String, ScriptError> {
        guard let context = JSContext() else { return .failure(.failed("No JavaScript engine")) }
        let failure = Failure()
        context.exceptionHandler = { _, exception in failure.set(exception?.toString() ?? "Script error") }

        context.setObject(clipText, forKeyedSubscript: "clipText" as NSString)
        let promptBlock: @convention(block) (String) -> Any = { text in prompt(text) as Any? ?? NSNull() }
        context.setObject(promptBlock, forKeyedSubscript: "prompt" as NSString)

        let clipMenu = JSValue(newObjectIn: context)
        let require: @convention(block) (String) -> Bool = { name in
            guard let library = Self.library(named: name, in: libFolders),
                  let code = try? String(contentsOf: library, encoding: .utf8) else { return false }
            context.evaluateScript(code)
            return failure.message == nil
        }
        let activateBlock: @convention(block) () -> Void = { activate() }
        clipMenu?.setObject(require, forKeyedSubscript: "require" as NSString)
        clipMenu?.setObject(activateBlock, forKeyedSubscript: "activate" as NSString)
        context.setObject(clipMenu, forKeyedSubscript: "ClipMenu" as NSString)
        // The v8cgi libraries publish their classes as `exports.Util`; here that is the global scope.
        context.evaluateScript("var exports = this;")

        let value = context.evaluateScript("(function () {\(source)\n})()")
        if let message = failure.message { return .failure(.failed(message)) }
        guard let value, value.isString, let text = value.toString() else { return .failure(.noResult) }
        return .success(text)
    }

    /// The first folder holding `name` (with `.js` added when missing). A name that climbs out
    /// of the folder is refused.
    private static func library(named name: String, in folders: [URL]) -> URL? {
        let file = (name as NSString).pathExtension == "js" ? name : name + ".js"
        for folder in folders {
            let root = folder.standardizedFileURL
            let candidate = root.appendingPathComponent(file).standardizedFileURL
            guard candidate.path.hasPrefix(root.path + "/") else { continue }
            if FileManager.default.isReadableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}

private final class Outcome: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<String, ScriptError>?

    func set(_ value: Result<String, ScriptError>) { lock.withLock { result = value } }
    func get() throws -> String { try lock.withLock { try result!.get() } }
}

private final class Failure: @unchecked Sendable {
    private let lock = NSLock()
    private var text: String?

    var message: String? { lock.withLock { text } }
    func set(_ value: String) { lock.withLock { if text == nil { text = value } } }
}
