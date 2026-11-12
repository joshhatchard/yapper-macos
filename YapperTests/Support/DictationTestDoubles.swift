import Foundation

@testable import Yapper

/// In-memory capture double. Records calls; results are configurable per test.
@MainActor
final class FakeAudioCapture: AudioCapturing {
    var startError: AudioCaptureError?
    var stopResult: Result<CapturedAudio, AudioCaptureError> = .success(.sample)
    /// When set, `startCapture` suspends until the gate opens (a slow microphone start).
    var startGate: Gate?
    var permission: PermissionStatus = .authorized
    /// What the user answers when the system prompt is shown.
    var permissionAfterRequest: PermissionStatus = .authorized

    private(set) var permissionRequests = 0
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var cancelCount = 0
    private(set) var discarded: [CapturedAudio] = []

    func permissionStatus() async -> PermissionStatus { permission }

    func requestPermission() async -> PermissionStatus {
        permissionRequests += 1
        permission = permissionAfterRequest
        return permission
    }

    func startCapture() async throws(AudioCaptureError) {
        startCount += 1
        await startGate?.wait()
        if let startError { throw startError }
    }

    func stopCapture() async throws(AudioCaptureError) -> CapturedAudio {
        stopCount += 1
        return try stopResult.get()
    }

    func cancelCapture() async {
        cancelCount += 1
    }

    func discard(_ audio: CapturedAudio) async {
        discarded.append(audio)
    }
}

/// Transcriber double returning a configured result.
@MainActor
final class FakeTranscriber: SpeechTranscribing {
    var result: Result<Transcript, TranscriptionError> = .success(Transcript(text: "hello world"))

    /// When true, `transcribe` suspends until `resume()` so tests can act mid-transcription.
    var suspendsUntilResumed = false

    private(set) var transcribed: [CapturedAudio] = []
    private var pending: CheckedContinuation<Void, Never>?

    var availability: TranscriptionAvailability = .ready
    var prepareError: TranscriptionError?
    /// When set, `prepare` suspends until the gate opens (a model download in progress).
    var prepareGate: Gate?

    private(set) var availabilityQueries: [Locale] = []
    private(set) var prepared: [Locale] = []

    func availability(for locale: Locale) async -> TranscriptionAvailability {
        availabilityQueries.append(locale)
        return availability
    }

    func prepare(for locale: Locale) async throws(TranscriptionError) {
        prepared.append(locale)
        await prepareGate?.wait()
        if let prepareError { throw prepareError }
        availability = .ready
    }

    func transcribe(_ audio: CapturedAudio, locale: Locale) async throws(TranscriptionError) -> Transcript {
        transcribed.append(audio)
        if suspendsUntilResumed {
            await withCheckedContinuation { pending = $0 }
        }
        return try result.get()
    }

    /// Yields until a transcription is suspended in `transcribe`.
    func waitUntilSuspended() async {
        while pending == nil { await Task.yield() }
    }

    func resume() {
        pending?.resume()
        pending = nil
    }
}

/// Inserter double. `target` is what the focused app looks like right now.
@MainActor
final class FakeTextInserter: TextInserting {
    struct Insertion: Equatable {
        let text: String
        let target: InsertionTarget
    }

    var target: InsertionTarget? = .sample
    var insertError: TextInsertionError?
    var accessibility: PermissionStatus = .authorized

    private(set) var insertions: [Insertion] = []
    private(set) var permissionRequests = 0

    func accessibilityStatus() -> PermissionStatus { accessibility }
    func requestAccessibilityPermission() { permissionRequests += 1 }
    func currentTarget() -> InsertionTarget? { target }

    func insert(_ text: String, into target: InsertionTarget) async throws(TextInsertionError) {
        if let insertError { throw insertError }
        insertions.append(Insertion(text: text, target: target))
    }
}

extension CapturedAudio {
    static let sample = CapturedAudio(
        fileURL: URL(fileURLWithPath: "/tmp/yapper-test.caf"),
        duration: .seconds(2)
    )
}

extension InsertionTarget {
    static let sample = InsertionTarget(processIdentifier: 4242, bundleIdentifier: "com.example.editor")
    static let other = InsertionTarget(processIdentifier: 5151, bundleIdentifier: "com.example.other")
}

/// In-memory preferences.
@MainActor
final class FakePreferencesStore: PreferencesStoring {
    var stored: AppPreferences?

    func load() -> AppPreferences? { stored }
    func save(_ preferences: AppPreferences) { stored = preferences }
}

/// Formatter double. By default tags the text with its mode so tests can see formatting happened.
@MainActor
final class FakeFormatter: TranscriptFormatting {
    struct Request: Equatable {
        let text: String
        let mode: TranscriptMode
    }

    var availabilityValue: FormattingAvailability = .ready
    var error: FormattingError?
    /// When set, `format` suspends until the gate opens (a slow on-device model).
    var gate: Gate?

    private(set) var requests: [Request] = []
    /// Requests whose task was cancelled (for example by the coordinator's timeout).
    private(set) var cancelledRequests = 0

    func availability() -> FormattingAvailability { availabilityValue }

    func format(_ text: String, as mode: TranscriptMode) async throws(FormattingError) -> String {
        requests.append(Request(text: text, mode: mode))
        await gate?.wait()
        if Task.isCancelled { cancelledRequests += 1 }
        if let error { throw error }
        return "[\(mode.rawValue)] \(text)"
    }
}
