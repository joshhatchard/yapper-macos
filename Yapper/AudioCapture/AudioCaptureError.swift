enum AudioCaptureError: Error, Equatable, Sendable {
    case permissionDenied
    case noInputDevice
    case alreadyCapturing
    case notCapturing
    case engineFailed(String)
    /// The temporary recording file could not be created or written.
    case storageFailed(String)
}
