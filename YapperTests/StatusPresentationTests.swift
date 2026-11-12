import Foundation
import Testing

@testable import Yapper

@Suite("StatusPresentation")
struct StatusPresentationTests {
    @Test(
        "each dictation state has a distinct menu-bar symbol",
        arguments: [
            (DictationState.idle, "mic"),
            (.recording, "mic.fill"),
            (.transcribing, "waveform"),
            (.formatting, "sparkles"),
            (.completedUnformatted(.failed("x")), "mic"),
            (.completed, "mic"),
            (.cancelled, "mic"),
            (.failed(.emptyTranscript), "exclamationmark.triangle"),
        ])
    func symbols(state: DictationState, symbol: String) {
        #expect(StatusPresentation.symbol(for: state) == symbol)
    }

    @Test("formatting states have their own titles")
    func formattingTitles() {
        #expect(StatusPresentation.title(for: .formatting) == "Formatting…")
        #expect(
            StatusPresentation.title(for: .completedUnformatted(.unavailable(.appleIntelligenceNotEnabled)))
                .contains("without formatting"))
    }

    @Test(
        "formatting readiness tells the user what to do",
        arguments: [
            (FormattingAvailability.appleIntelligenceNotEnabled, "Apple Intelligence"),
            (.deviceNotEligible, "this Mac"),
            (.modelNotReady, "downloading"),
        ])
    func formattingReadiness(availability: FormattingAvailability, mentions: String) throws {
        #expect(try #require(StatusPresentation.formattingNote(availability)).contains(mentions))
    }

    @Test("no formatting note when the model is ready or still being checked")
    func noNoteWhenReady() {
        #expect(StatusPresentation.formattingNote(.ready) == nil)
        #expect(StatusPresentation.formattingNote(nil) == nil)
    }

    @Test("each mode has a one-line description", arguments: TranscriptMode.allCases)
    func modeSummaries(mode: TranscriptMode) {
        #expect(!StatusPresentation.summary(for: mode).isEmpty)
    }

    @Test("a failed state shows its failure message")
    func failedTitleIsMessage() {
        let failure = DictationFailure.textInsertion(.unsupportedFocusedElement)
        #expect(StatusPresentation.title(for: .failed(failure)) == StatusPresentation.message(for: failure))
        #expect(StatusPresentation.title(for: .recording) == "Recording…")
    }

    @Test(
        "failure messages say what to do",
        arguments: [
            (DictationFailure.textInsertion(.accessibilityPermissionDenied), "Accessibility"),
            (.audioCapture(.permissionDenied), "Microphone"),
            (.audioCapture(.noInputDevice), "microphone"),
            (.transcription(.modelUnavailable(Locale(identifier: "en_US"))), "model"),
            (.transcription(.unsupportedLocale(Locale(identifier: "xx"))), "language"),
            (.textInsertion(.unsupportedFocusedElement), "text field"),
            (.textInsertion(.noFocusedElement), "text field"),
            (.textInsertion(.targetNoLongerFocused), "switched"),
            (.textInsertion(.secureInputActive), "password"),
            (.noInsertionTarget, "app"),
            (.emptyTranscript, "No speech"),
        ])
    func failureMessages(failure: DictationFailure, mentions: String) {
        #expect(StatusPresentation.message(for: failure).contains(mentions))
    }

    @Test(
        "readiness explains the model state",
        arguments: [
            (TranscriptionAvailability?.none, "Checking"),
            (.ready, "ready"),
            (.modelNotInstalled, "download"),
            (.unsupportedLocale, "not supported"),
            (.unavailable, "unavailable"),
        ])
    func readiness(availability: TranscriptionAvailability?, mentions: String) {
        #expect(StatusPresentation.readiness(availability, locale: Locale(identifier: "en_AU")).contains(mentions))
    }

    @Test("the push-to-talk hint names the fn (Globe) + Shift gesture")
    func pushToTalkHint() {
        #expect(StatusPresentation.pushToTalkHint == "Hold fn (Globe) + Shift to dictate into the focused text field.")
    }

    @Test(
        "shortcut errors explain the problem",
        arguments: [
            (ShortcutError.permissionDenied, "Input Monitoring"),
            (.eventTapUnavailable, "Input Monitoring"),
            (.eventTapDisabled, "stopped"),
        ])
    func shortcutErrors(error: ShortcutError, mentions: String) {
        #expect(StatusPresentation.message(for: error).contains(mentions))
    }
}
