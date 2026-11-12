import ApplicationServices

/// Pure translation of AX failures into app errors.
enum AccessibilityErrorMapping {
    static func error(for code: AXError) -> TextInsertionError {
        switch code {
        case .apiDisabled:
            .accessibilityPermissionDenied
        case .noValue:
            .noFocusedElement
        case .attributeUnsupported, .notImplemented:
            .unsupportedFocusedElement
        case .invalidUIElement:
            .targetNoLongerFocused
        default:
            .insertionFailed
        }
    }
}
