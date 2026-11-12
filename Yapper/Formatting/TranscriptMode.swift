/// How a finished transcript is shaped before it is inserted. Chosen in the menu, stored in preferences.
enum TranscriptMode: String, CaseIterable, Codable, Sendable {
    /// The transcript exactly as recognized.
    case standard
    /// Cleaned up into a clear message for an AI assistant (filler removed, requests structured).
    case ai
    /// Condensed into bullet-point notes.
    case notes

    var title: String {
        switch self {
        case .standard: "Default"
        case .ai: "AI"
        case .notes: "Notes"
        }
    }
}
