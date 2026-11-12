import Foundation

/// Seam over the running-application queries used for insertion. Real: `SystemWorkspace`.
@MainActor
protocol WorkspaceAPI: AnyObject {
    /// The app that receives keyboard input right now, if any.
    func frontmostApplication() -> InsertionTarget?
    func isRunning(_ processIdentifier: pid_t) -> Bool
    /// This app's own process identifier; it is never a dictation target.
    var ownProcessIdentifier: pid_t { get }
}
