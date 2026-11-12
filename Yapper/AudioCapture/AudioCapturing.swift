/// Microphone capture lifecycle. Owns recorded audio until `discard(_:)` is called.
protocol AudioCapturing: Sendable {
    func permissionStatus() async -> PermissionStatus
    func requestPermission() async -> PermissionStatus
    func startCapture() async throws(AudioCaptureError)
    func stopCapture() async throws(AudioCaptureError) -> CapturedAudio
    func cancelCapture() async
    func discard(_ audio: CapturedAudio) async
}
