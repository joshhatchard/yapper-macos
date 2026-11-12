import AVFoundation
import Synchronization

@testable import Yapper

/// Stands in for the microphone. Tests push generated buffers with `deliver(_:)`.
final class FakeAudioInput: AudioInputSource {
    struct Snapshot {
        var format = TestAudio.format(sampleRate: 48_000, channels: 1)
        var prepareError: AudioCaptureError?
        var startError: AudioCaptureError?
        var prepareCount = 0
        var stopCount = 0
        var onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?
        var isRunning: Bool { onBuffer != nil }
    }

    private let state = Mutex(Snapshot())

    var snapshot: Snapshot { state.withLock { $0 } }

    func configure(_ change: (inout Snapshot) -> Void) {
        state.withLock { change(&$0) }
    }

    func prepare() throws(AudioCaptureError) -> AVAudioFormat {
        let result: Result<AVAudioFormat, AudioCaptureError> = state.withLock { state in
            state.prepareCount += 1
            if let error = state.prepareError { return .failure(error) }
            return .success(state.format)
        }
        return try result.get()
    }

    func start(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws(AudioCaptureError) {
        let error = state.withLock { state in
            if state.startError == nil { state.onBuffer = onBuffer }
            return state.startError
        }
        if let error { throw error }
    }

    func stop() {
        state.withLock { state in
            state.stopCount += 1
            state.onBuffer = nil
        }
    }

    /// Delivers a buffer the way the engine tap would. No-op when not running.
    func deliver(_ buffer: AVAudioPCMBuffer) {
        state.withLock { $0.onBuffer }?(buffer)
    }
}

struct FixedMicrophoneAuthorization: MicrophoneAuthorizing {
    var current: PermissionStatus = .authorized

    func status() -> PermissionStatus { current }
    func request() async -> PermissionStatus { current }
}
