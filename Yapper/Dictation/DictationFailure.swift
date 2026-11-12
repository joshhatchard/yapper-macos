/// Reason a dictation session ended without inserting text.
enum DictationFailure: Error, Equatable, Sendable {
    case audioCapture(AudioCaptureError)
    case transcription(TranscriptionError)
    case textInsertion(TextInsertionError)
    case emptyTranscript
    case noInsertionTarget
}
