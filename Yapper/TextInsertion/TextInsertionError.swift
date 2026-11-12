enum TextInsertionError: Error, Equatable, Sendable {
    case accessibilityPermissionDenied
    case targetNoLongerFocused
    case targetTerminated
    /// The target app has no focused UI element (nothing to type into).
    case noFocusedElement
    /// The focused element does not accept inserted text (not editable, secure field, or no AX support).
    case unsupportedFocusedElement
    case insertionFailed
    /// macOS Secure Input is on (a password field has the keyboard), so the paste fallback is refused.
    case secureInputActive
}
