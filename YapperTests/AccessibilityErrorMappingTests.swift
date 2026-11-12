import ApplicationServices
import Testing

@testable import Yapper

@Suite("AccessibilityErrorMapping")
struct AccessibilityErrorMappingTests {
    @Test(
        "AX errors map to actionable insertion errors",
        arguments: [
            (AXError.apiDisabled, TextInsertionError.accessibilityPermissionDenied),
            (.noValue, .noFocusedElement),
            (.attributeUnsupported, .unsupportedFocusedElement),
            (.notImplemented, .unsupportedFocusedElement),
            (.invalidUIElement, .targetNoLongerFocused),
            (.cannotComplete, .insertionFailed),
            (.failure, .insertionFailed),
            (.illegalArgument, .insertionFailed),
        ])
    func mapsAXErrors(code: AXError, expected: TextInsertionError) {
        #expect(AccessibilityErrorMapping.error(for: code) == expected)
    }
}
