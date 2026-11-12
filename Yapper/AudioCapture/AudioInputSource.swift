import AVFoundation

/// The microphone side of capture: produces PCM buffers in a fixed format until stopped.
/// The seam exists so capture lifecycle and file handling are testable without audio hardware.
protocol AudioInputSource: AnyObject, Sendable {
    /// Selects the current input device and returns the format `start` will deliver.
    func prepare() throws(AudioCaptureError) -> AVAudioFormat
    /// Starts delivering buffers. `onBuffer` is called on an audio thread, never concurrently with itself.
    func start(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws(AudioCaptureError)
    /// Stops delivery and releases the device. Safe to call when not prepared or already stopped.
    func stop()
}
