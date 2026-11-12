import Foundation

enum TranscriptionError: Error, Equatable, Sendable {
    case unsupportedLocale(Locale)
    case modelUnavailable(Locale)
    case permissionDenied
    case recognitionFailed(String)
    case cancelled
}
