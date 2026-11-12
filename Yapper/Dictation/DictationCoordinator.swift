import Foundation
import Observation

/// Coordinates idle -> recording -> transcribing -> (formatting) -> completed/failed/cancelled.
/// Depends only on app-owned protocols so it is testable without hardware or permissions.
@MainActor
@Observable
final class DictationCoordinator {
    private(set) var state: DictationState = .idle
    var locale: Locale
    /// Applied to sessions that start after it changes.
    var mode: TranscriptMode = .standard

    @ObservationIgnored private let audioCapture: any AudioCapturing
    @ObservationIgnored private let transcriber: any SpeechTranscribing
    @ObservationIgnored private let textInserter: any TextInserting
    @ObservationIgnored private let formatter: any TranscriptFormatting
    @ObservationIgnored private var target: InsertionTarget?
    @ObservationIgnored private var sessionMode: TranscriptMode = .standard
    /// After this, formatting is cancelled and the raw transcript is inserted.
    @ObservationIgnored private let formattingTimeout: Duration

    init(
        audioCapture: any AudioCapturing,
        transcriber: any SpeechTranscribing,
        textInserter: any TextInserting,
        formatter: any TranscriptFormatting,
        locale: Locale,
        formattingTimeout: Duration = .seconds(10)
    ) {
        self.audioCapture = audioCapture
        self.transcriber = transcriber
        self.textInserter = textInserter
        self.formatter = formatter
        self.formattingTimeout = formattingTimeout
        self.locale = locale
    }

    /// Routes push-to-talk shortcut events to start/finish.
    /// Callers should await each event before handling the next so press/release stay ordered.
    func handle(_ event: ShortcutEvent) async {
        switch event {
        case .pressed:
            await start()
        case .released:
            await finish()
        }
    }

    /// Captures the insertion target and begins recording. Fails before opening the microphone when
    /// insertion cannot succeed (no Accessibility trust, no target). Never prompts for permission.
    func start() async {
        guard !state.isActive else { return }
        guard textInserter.accessibilityStatus() == .authorized else {
            state = .failed(.textInsertion(.accessibilityPermissionDenied))
            return
        }
        guard let currentTarget = textInserter.currentTarget() else {
            state = .failed(.noInsertionTarget)
            return
        }
        do {
            try await audioCapture.startCapture()
        } catch {
            state = .failed(.audioCapture(error))
            return
        }
        target = currentTarget
        sessionMode = mode
        state = .recording
    }

    /// Stops recording, transcribes on-device, formats it for the session's mode (on-device; on failure
    /// the raw transcript is used so nothing said is lost), and inserts it.
    func finish() async {
        guard state == .recording, let target else { return }
        let audio: CapturedAudio
        do {
            audio = try await audioCapture.stopCapture()
        } catch {
            state = .failed(.audioCapture(error))
            return
        }
        state = .transcribing
        let outcome = await deliver(audio, to: target)
        await audioCapture.discard(audio)
        if let outcome { state = outcome }
    }

    /// Transcribes and inserts. Returns the terminal state, or nil if the session was cancelled meanwhile.
    /// Caller owns audio cleanup.
    private func deliver(_ audio: CapturedAudio, to target: InsertionTarget) async -> DictationState? {
        let transcription = await transcribe(audio)
        guard state == .transcribing else { return nil }
        let transcript: Transcript
        switch transcription {
        case .success(let value):
            transcript = value
        case .failure(let error):
            return .failed(.transcription(error))
        }
        guard !transcript.text.allSatisfy(\.isWhitespace) else { return .failed(.emptyTranscript) }

        var text = transcript.text
        var formattingError: FormattingError?
        if sessionMode != .standard {
            state = .formatting
            switch await formatWithinTimeLimit(transcript.text, as: sessionMode) {
            case .success(let formatted): text = formatted
            case .failure(let error): formattingError = error
            }
            guard state == .formatting else { return nil }
        }

        do {
            try await textInserter.insert(text, into: target)
        } catch {
            return .failed(.textInsertion(error))
        }
        return formattingError.map(DictationState.completedUnformatted) ?? .completed
    }

    /// Races the formatter against `formattingTimeout`. On timeout the formatting task is cancelled and
    /// `.timedOut` is returned at once, even if the formatter is slow to notice the cancellation.
    private func formatWithinTimeLimit(_ text: String, as mode: TranscriptMode) async -> Result<String, FormattingError>
    {
        let formatter = formatter
        let timeout = formattingTimeout
        return await withCheckedContinuation { continuation in
            let resumed = ResumeOnce(continuation)
            let work = Task { @MainActor in
                let result: Result<String, FormattingError>
                do throws(FormattingError) {
                    result = .success(try await formatter.format(text, as: mode))
                } catch {
                    result = .failure(error)
                }
                resumed.resume(with: result)
            }
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                guard !resumed.isDone else { return }
                work.cancel()
                resumed.resume(with: .failure(.timedOut))
            }
        }
    }

    private func transcribe(_ audio: CapturedAudio) async -> Result<Transcript, TranscriptionError> {
        do {
            return .success(try await transcriber.transcribe(audio, locale: locale))
        } catch {
            return .failure(error)
        }
    }

    /// Aborts the active session and releases capture resources.
    func cancel() async {
        guard state.isActive else { return }
        await audioCapture.cancelCapture()
        state = .cancelled
    }
}

/// Resumes a continuation with the first result only; later results are dropped.
@MainActor
private final class ResumeOnce {
    private var continuation: CheckedContinuation<Result<String, FormattingError>, Never>?

    init(_ continuation: CheckedContinuation<Result<String, FormattingError>, Never>) {
        self.continuation = continuation
    }

    var isDone: Bool { continuation == nil }

    func resume(with result: Result<String, FormattingError>) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}
