/// Progress of a user-approved speech-model download. A download needs two user actions:
/// request (shows what will happen) then confirm.
enum ModelInstallState: Equatable, Sendable {
    case idle
    case awaitingConfirmation
    case installing
    case failed(TranscriptionError)
}
