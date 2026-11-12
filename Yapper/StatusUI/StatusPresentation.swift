import Foundation

/// User-facing text and symbols for app state. Pure, so the menu content stays declarative.
enum StatusPresentation {
    static func title(for state: DictationState) -> String {
        switch state {
        case .idle: "Ready"
        case .recording: "Recording…"
        case .transcribing: "Transcribing…"
        case .formatting: "Formatting…"
        case .completed: "Inserted"
        case .completedUnformatted(let error): "Inserted without formatting: \(reason(for: error))"
        case .cancelled: "Cancelled"
        case .failed(let failure): message(for: failure)
        }
    }

    static func symbol(for state: DictationState) -> String {
        switch state {
        case .idle, .completed, .completedUnformatted, .cancelled: "mic"
        case .recording: "mic.fill"
        case .transcribing: "waveform"
        case .formatting: "sparkles"
        case .failed: "exclamationmark.triangle"
        }
    }

    static func message(for failure: DictationFailure) -> String {
        switch failure {
        case .audioCapture(let error): message(for: error)
        case .transcription(let error): message(for: error)
        case .textInsertion(let error): message(for: error)
        case .emptyTranscript: "No speech was recognized."
        case .noInsertionTarget: "No app to type into. Focus a text field in another app first."
        }
    }

    static func readiness(_ availability: TranscriptionAvailability?, locale: Locale) -> String {
        let language = locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
        return switch availability {
        case nil: "Checking speech model…"
        case .ready: "On-device speech model ready (\(language))"
        case .modelNotInstalled: "Speech model for \(language) needs a one-time download"
        case .unsupportedLocale: "\(language) is not supported for on-device dictation"
        case .unavailable: "On-device speech recognition is unavailable on this Mac"
        }
    }

    static func summary(for mode: TranscriptMode) -> String {
        switch mode {
        case .standard: "Inserts exactly what you said."
        case .ai: "Cleans up your words into a clear prompt for an AI assistant."
        case .notes: "Turns what you said into short bullet-point notes."
        }
    }

    /// Why AI and Notes modes cannot format right now; nil when they can (or it is still being checked).
    static func formattingNote(_ availability: FormattingAvailability?) -> String? {
        switch availability {
        case nil, .ready:
            nil
        case .appleIntelligenceNotEnabled:
            "Turn on Apple Intelligence in System Settings › Apple Intelligence & Siri to use this mode. "
                + "Until then, the plain transcript is inserted."
        case .deviceNotEligible:
            "This mode needs Apple Intelligence, which this Mac does not support. The plain transcript is inserted."
        case .modelNotReady:
            "Apple Intelligence is still downloading its model. The plain transcript is inserted until it is ready."
        case .unavailable:
            "On-device formatting is unavailable right now. The plain transcript is inserted."
        }
    }

    private static func reason(for error: FormattingError) -> String {
        switch error {
        case .unavailable(.appleIntelligenceNotEnabled): "Apple Intelligence is off."
        case .unavailable(.modelNotReady): "Apple Intelligence is still downloading."
        case .unavailable: "on-device formatting is unavailable."
        case .tooLong: "the dictation was too long to format."
        case .refused: "the on-device model declined this text."
        case .emptyResult: "the model returned nothing."
        case .notARewrite: "the model tried to answer instead of rewriting."
        case .timedOut: "formatting took too long."
        case .failed: "the on-device model failed."
        }
    }

    static let pushToTalkHint = "Hold fn (Globe) + Shift to dictate into the focused text field."

    static func message(for error: ShortcutError) -> String {
        switch error {
        case .permissionDenied:
            "Push-to-talk needs Input Monitoring. Allow it in the menu or System Settings › Input Monitoring."
        case .eventTapUnavailable:
            "macOS did not let Yapper watch fn + Shift. Check Input Monitoring, then quit and reopen Yapper."
        case .eventTapDisabled:
            "macOS stopped Yapper's fn + Shift listener. Reopen this menu to try again."
        }
    }

    private static func message(for error: AudioCaptureError) -> String {
        switch error {
        case .permissionDenied: "Microphone access is off. Allow it in the menu or System Settings › Microphone."
        case .noInputDevice: "No microphone found."
        case .alreadyCapturing, .notCapturing: "Recording got out of sync. Try again."
        case .engineFailed(let detail): "Could not start the microphone: \(detail)"
        case .storageFailed(let detail): "Could not save the recording: \(detail)"
        }
    }

    private static func message(for error: TranscriptionError) -> String {
        switch error {
        case .unsupportedLocale: "This language is not supported for on-device dictation."
        case .modelUnavailable: "The speech model is not installed. Download it from the menu."
        case .permissionDenied: "Speech recognition access is off."
        case .recognitionFailed(let detail): "Transcription failed: \(detail)"
        case .cancelled: "Transcription was cancelled."
        }
    }

    private static func message(for error: TextInsertionError) -> String {
        switch error {
        case .accessibilityPermissionDenied:
            "Accessibility access is off. Allow it in the menu or System Settings › Accessibility."
        case .targetNoLongerFocused: "You switched apps while dictating, so nothing was inserted."
        case .targetTerminated: "The app you were dictating into quit."
        case .noFocusedElement: "No text field is focused in that app."
        case .unsupportedFocusedElement: "The focused control is not a text field Yapper can type into."
        case .insertionFailed: "The app did not accept the text."
        case .secureInputActive: "A password field is active, so Yapper did not paste the text."
        }
    }
}
