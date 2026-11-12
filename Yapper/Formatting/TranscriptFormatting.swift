/// Rewrites a transcript for a `TranscriptMode` on this Mac. Real: `FoundationModelsFormatter`.
@MainActor
protocol TranscriptFormatting: AnyObject {
    /// Whether the on-device model can run now. Never prompts or downloads.
    func availability() -> FormattingAvailability
    /// Returns the rewritten text. Text never leaves the Mac.
    func format(_ text: String, as mode: TranscriptMode) async throws(FormattingError) -> String
}

enum FormattingAvailability: Equatable, Sendable {
    case ready
    case appleIntelligenceNotEnabled
    case deviceNotEligible
    /// Apple Intelligence is on but the model is still downloading or preparing.
    case modelNotReady
    case unavailable
}

enum FormattingError: Error, Equatable, Sendable {
    case unavailable(FormattingAvailability)
    /// The transcript is longer than the on-device model's context window.
    case tooLong
    /// The model's safety guardrails declined the text.
    case refused
    /// The model returned nothing usable.
    case emptyResult
    /// The model answered or carried out the dictation instead of rewriting it.
    case notARewrite
    /// The model did not finish within the coordinator's time limit.
    case timedOut
    case failed(String)
}
