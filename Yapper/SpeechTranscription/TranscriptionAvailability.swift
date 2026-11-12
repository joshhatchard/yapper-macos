enum TranscriptionAvailability: Equatable, Sendable {
    case ready
    case modelNotInstalled
    case unsupportedLocale
    case unavailable
}
