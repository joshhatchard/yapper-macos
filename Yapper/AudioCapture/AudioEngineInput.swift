import AVFoundation
import Synchronization

/// Microphone input through `AVAudioEngine`'s input node (the system default input device).
///
/// A fresh engine is created per session so a changed default device or format is picked up.
/// Not handled yet: `AVAudioEngineConfigurationChange` mid-recording (device unplugged or switched).
/// The engine then stops delivering buffers and `stop()` keeps whatever was recorded until then.
final class AudioEngineInput: AudioInputSource {
    private static let bus: AVAudioNodeBus = 0
    private static let bufferSize: AVAudioFrameCount = 4_096

    private let engine = Mutex<AVAudioEngine?>(nil)

    init() {}

    func prepare() throws(AudioCaptureError) -> AVAudioFormat {
        let newEngine = AVAudioEngine()
        let format = newEngine.inputNode.outputFormat(forBus: Self.bus)
        guard format.channelCount > 0, format.sampleRate > 0 else { throw .noInputDevice }
        engine.withLock { $0 = newEngine }
        return format
    }

    func start(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws(AudioCaptureError) {
        let result: Result<Void, AudioCaptureError> = engine.withLock { engine in
            guard let engine else { return .failure(.engineFailed("input was not prepared")) }
            let input = engine.inputNode
            input.installTap(onBus: Self.bus, bufferSize: Self.bufferSize, format: nil) { @Sendable buffer, _ in
                onBuffer(buffer)
            }
            engine.prepare()
            do {
                try engine.start()
                return .success(())
            } catch {
                input.removeTap(onBus: Self.bus)
                return .failure(.engineFailed(String(describing: error)))
            }
        }
        try result.get()
    }

    func stop() {
        engine.withLock { engine in
            engine?.inputNode.removeTap(onBus: Self.bus)
            engine?.stop()
            engine = nil
        }
    }
}
