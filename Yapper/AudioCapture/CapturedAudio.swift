import Foundation

/// A finished recording in a temporary file. Never persisted beyond the session.
struct CapturedAudio: Equatable, Sendable {
    let fileURL: URL
    let duration: Duration
}
