/// Observable lifecycle of a single dictation session.
enum DictationState: Equatable, Sendable {
    case idle
    case recording
    case transcribing
    /// AI or Notes mode: the on-device model is rewriting the transcript.
    case formatting
    case completed
    /// Inserted the raw transcript because formatting was unavailable or failed.
    case completedUnformatted(FormattingError)
    case failed(DictationFailure)
    case cancelled
}

extension DictationState {
    /// True while a session owns the microphone or is processing its audio.
    var isActive: Bool {
        switch self {
        case .recording, .transcribing, .formatting:
            true
        case .idle, .completed, .completedUnformatted, .failed, .cancelled:
            false
        }
    }
}
