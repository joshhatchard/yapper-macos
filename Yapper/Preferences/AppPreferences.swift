import Foundation

/// User settings only. Never contains audio or transcripts. The push-to-talk gesture (hold fn + Shift)
/// is fixed, so it is not stored; data saved by older builds with a `shortcut` key still decodes.
struct AppPreferences: Equatable, Sendable, Codable {
    var localeIdentifier: String
    var transcriptMode: TranscriptMode = .standard

    private enum CodingKeys: String, CodingKey {
        case localeIdentifier
        case transcriptMode
    }
}

extension AppPreferences {
    static func defaults(locale: Locale) -> AppPreferences {
        AppPreferences(localeIdentifier: locale.identifier)
    }

    /// A missing or unknown mode (older builds, hand edits) decodes as `.standard` instead of failing,
    /// so the stored locale is never lost.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        localeIdentifier = try container.decode(String.self, forKey: .localeIdentifier)
        let mode = try? container.decodeIfPresent(String.self, forKey: .transcriptMode)
        transcriptMode = mode.flatMap(TranscriptMode.init(rawValue:)) ?? .standard
    }
}
