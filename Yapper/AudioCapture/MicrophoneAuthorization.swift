import AVFoundation

/// Reads and requests the system microphone authorization (TCC).
protocol MicrophoneAuthorizing: Sendable {
    /// Current status. Never shows a prompt.
    func status() -> PermissionStatus
    /// Shows the system prompt if the user has not decided yet; otherwise returns the stored decision.
    func request() async -> PermissionStatus
}

/// `AVCaptureDevice`-backed authorization for audio input.
struct SystemMicrophoneAuthorization: MicrophoneAuthorizing {
    func status() -> PermissionStatus {
        PermissionStatus(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    func request() async -> PermissionStatus {
        guard status() == .notDetermined else { return status() }
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        return status()
    }
}

extension PermissionStatus {
    init(_ status: AVAuthorizationStatus) {
        switch status {
        case .authorized:
            self = .authorized
        case .denied:
            self = .denied
        case .restricted:
            self = .restricted
        case .notDetermined:
            self = .notDetermined
        @unknown default:
            self = .denied
        }
    }
}
