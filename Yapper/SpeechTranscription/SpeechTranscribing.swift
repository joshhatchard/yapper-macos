import Foundation

/// On-device speech-to-text. Implementations must never fall back to server recognition.
protocol SpeechTranscribing: Sendable {
    func availability(for locale: Locale) async -> TranscriptionAvailability
    /// Ensures on-device model assets for `locale` are installed.
    func prepare(for locale: Locale) async throws(TranscriptionError)
    func transcribe(_ audio: CapturedAudio, locale: Locale) async throws(TranscriptionError) -> Transcript
}
