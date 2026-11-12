/// Input Monitoring (listen-event) permission, required for the fn + Shift event tap.
@MainActor
protocol InputMonitoringAuthorizing: AnyObject {
    /// Current status. Never prompts.
    func status() -> PermissionStatus
    /// May show the system prompt (which links to System Settings). Call only from a user action.
    func request()
}
