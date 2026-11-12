/// Global push-to-talk input gated by Input Monitoring. Real implementation: `PushToTalkMonitor`
/// over `CoreGraphicsModifierTap` and `SystemInputMonitoringAuthorization`.
@MainActor
protocol ShortcutMonitoring: AnyObject {
    var isRunning: Bool { get }
    /// Never prompts.
    func permissionStatus() -> PermissionStatus
    /// May show the system prompt. Call only from a user action. Returns the status afterwards.
    func requestPermission() -> PermissionStatus
    /// Starts delivering paired press/release events. Throws `.permissionDenied` without touching the
    /// OS when Input Monitoring is not authorized. `onFailure` reports a tap that stopped for good.
    func start(
        onEvent: @escaping @MainActor (ShortcutEvent) -> Void,
        onFailure: @escaping @MainActor (ShortcutError) -> Void
    ) throws(ShortcutError)
    /// Stops events; emits a final `.released` if the gesture was held.
    func stop()
}
