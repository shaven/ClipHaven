import ClipHavenCore
import Foundation

/// `ClipHaven --import-clipmenu-history <clips.data> <history.sqlite> [limit]`
///
/// Reads ClipMenu's history in a process of its own, so the memory a 900 MB file needs goes back to
/// the system when it exits and the menu-bar app never holds it. Prints counts as JSON.
enum HistoryImportMode {
    static let flag = "--import-clipmenu-history"

    static func runIfRequested() {
        let args = CommandLine.arguments
        guard args.count >= 4, args[1] == flag else { return }
        do {
            let store = try HistoryStore(url: URL(fileURLWithPath: args[3]), limits: Preferences().limits)
            let limit = args.count > 4 ? Int(args[4]) : nil
            let counts = try ClipMenuHistory.importFile(at: URL(fileURLWithPath: args[2]), into: store, limit: limit)
            FileHandle.standardOutput.write(try JSONEncoder().encode(counts))
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("\(error)".utf8))
            exit(1)
        }
    }

    /// Runs the import in a child process and waits for it off the main thread.
    static func run(source: URL, database: URL, limit: Int?) async -> Result<HistoryImportCounts, ImportFailure> {
        await Task.detached {
            guard let executable = Bundle.main.executableURL else { return .failure(ImportFailure(message: "no executable")) }
            let process = Process()
            process.executableURL = executable
            process.arguments = [flag, source.path, database.path] + (limit.map { [String($0)] } ?? [])
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            do {
                try process.run()
                let data = out.fileHandleForReading.readDataToEndOfFile()
                let message = err.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    return .failure(ImportFailure(message: String(decoding: message, as: UTF8.self)))
                }
                return .success(try JSONDecoder().decode(HistoryImportCounts.self, from: data))
            } catch {
                return .failure(ImportFailure(message: "\(error)"))
            }
        }.value
    }
}

struct ImportFailure: Error, Sendable {
    let message: String
}
