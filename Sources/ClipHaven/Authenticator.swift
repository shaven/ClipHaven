import ClipHavenCore
import Foundation
import LocalAuthentication

/// Touch ID, else the Mac password (`.deviceOwnerAuthentication`). A fresh `LAContext` for every
/// call, so a success never carries over to the next paste.
final class TouchIDAuthenticator: Authenticator, @unchecked Sendable {
    /// The context of the last successful authentication, which the Keychain read reuses so the
    /// owner is asked once, not twice.
    private(set) var lastContext: LAContext?

    func authenticate(reason: String) -> Bool {
        lastContext = nil
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            NSLog("ClipHaven: authentication unavailable: \(error?.localizedDescription ?? "unknown")")
            return false
        }
        let outcome = Outcome()
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
            outcome.succeeded = success
            outcome.done.signal()
        }
        outcome.done.wait()
        if outcome.succeeded { lastContext = context }
        return outcome.succeeded
    }

    private final class Outcome: @unchecked Sendable {
        var succeeded = false
        let done = DispatchSemaphore(value: 0)
    }
}

/// Runs the restore on the main queue after the delay.
struct MainScheduler: Scheduler {
    func after(_ seconds: TimeInterval, _ work: @escaping () -> Void) {
        let box = Work(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            MainActor.assumeIsolated { box.run() }
        }
    }

    private final class Work: @unchecked Sendable {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
    }
}
