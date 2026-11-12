import Foundation

/// The application that was frontmost when dictation started.
struct InsertionTarget: Equatable, Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
}
