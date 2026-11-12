import AppKit

/// `WorkspaceAPI` backed by `NSWorkspace` / `NSRunningApplication`.
@MainActor
final class SystemWorkspace: WorkspaceAPI {
    func frontmostApplication() -> InsertionTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return InsertionTarget(processIdentifier: app.processIdentifier, bundleIdentifier: app.bundleIdentifier)
    }

    func isRunning(_ processIdentifier: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: processIdentifier) else { return false }
        return !app.isTerminated
    }

    var ownProcessIdentifier: pid_t { ProcessInfo.processInfo.processIdentifier }
}
