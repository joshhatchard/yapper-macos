import Foundation
import Speech

/// Pure translation from Apple Speech framework values to app-owned types.
enum SpeechAnalyzerMapping {
    static func availability(
        serviceAvailable: Bool,
        assetStatus: AssetInventory.Status,
        localeInstalled: Bool
    ) -> TranscriptionAvailability {
        guard serviceAvailable else { return .unavailable }
        switch assetStatus {
        case .unsupported:
            return .unsupportedLocale
        case .installed:
            return .ready
        case .supported, .downloading:
            return localeInstalled ? .ready : .modelNotInstalled
        @unknown default:
            return .unavailable
        }
    }

    static func error(from error: any Error, locale: Locale) -> TranscriptionError {
        if let error = error as? TranscriptionError { return error }
        if error is CancellationError { return .cancelled }

        let nsError = error as NSError
        if nsError.domain == SFSpeechError.errorDomain {
            switch SFSpeechError.Code(rawValue: nsError.code) {
            case .cannotAllocateUnsupportedLocale:
                return .unsupportedLocale(locale)
            case .noModel, .assetLocaleNotAllocated, .tooManyAssetLocalesAllocated:
                return .modelUnavailable(locale)
            default:
                break
            }
        }
        return .recognitionFailed(nsError.localizedDescription)
    }

    static func transcript(fromFinalSegments segments: [String]) -> Transcript {
        Transcript(text: segments.joined().trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
