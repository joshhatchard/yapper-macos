enum ShortcutError: Error, Equatable, Sendable {
    /// Input Monitoring is not granted, so the fn + Shift tap was not installed.
    case permissionDenied
    /// macOS refused to create the event tap (`CGEventTapCreate` returned nil).
    case eventTapUnavailable
    /// macOS disabled the event tap and it could not be re-enabled.
    case eventTapDisabled
}
