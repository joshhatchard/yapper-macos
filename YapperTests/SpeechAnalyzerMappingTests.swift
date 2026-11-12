import Foundation
import Speech
import Testing

@testable import Yapper

@Suite("SpeechAnalyzer availability mapping")
struct SpeechAnalyzerAvailabilityMappingTests {
    @Test("service unavailable wins over any asset status")
    func serviceUnavailable() {
        let result = SpeechAnalyzerMapping.availability(
            serviceAvailable: false, assetStatus: .installed, localeInstalled: true)

        #expect(result == .unavailable)
    }

    @Test("unsupported asset status maps to unsupported locale")
    func unsupportedLocale() {
        let result = SpeechAnalyzerMapping.availability(
            serviceAvailable: true, assetStatus: .unsupported, localeInstalled: false)

        #expect(result == .unsupportedLocale)
    }

    @Test("installed asset status is ready")
    func installedIsReady() {
        let result = SpeechAnalyzerMapping.availability(
            serviceAvailable: true, assetStatus: .installed, localeInstalled: false)

        #expect(result == .ready)
    }

    // Verified at runtime on macOS 26.6.2: status reports `.supported` for a locale listed in
    // `SpeechTranscriber.installedLocales` until the process reserves it, yet analysis succeeds.
    @Test("supported status with locale already installed on the system is ready")
    func supportedButInstalledIsReady() {
        let result = SpeechAnalyzerMapping.availability(
            serviceAvailable: true, assetStatus: .supported, localeInstalled: true)

        #expect(result == .ready)
    }

    @Test("supported without installed locale needs model install")
    func supportedNeedsInstall() {
        let result = SpeechAnalyzerMapping.availability(
            serviceAvailable: true, assetStatus: .supported, localeInstalled: false)

        #expect(result == .modelNotInstalled)
    }

    @Test("downloading without installed locale needs model install")
    func downloadingNeedsInstall() {
        let result = SpeechAnalyzerMapping.availability(
            serviceAvailable: true, assetStatus: .downloading, localeInstalled: false)

        #expect(result == .modelNotInstalled)
    }
}

@Suite("SpeechAnalyzer error mapping")
struct SpeechAnalyzerErrorMappingTests {
    let locale = Locale(identifier: "en_AU")

    func speechError(_ code: SFSpeechError.Code) -> NSError {
        NSError(domain: SFSpeechError.errorDomain, code: code.rawValue, userInfo: [NSLocalizedDescriptionKey: "speech"])
    }

    @Test("task cancellation maps to cancelled")
    func cancellation() {
        #expect(SpeechAnalyzerMapping.error(from: CancellationError(), locale: locale) == .cancelled)
    }

    @Test("app transcription errors pass through unchanged")
    func passThrough() {
        let error = TranscriptionError.permissionDenied

        #expect(SpeechAnalyzerMapping.error(from: error, locale: locale) == .permissionDenied)
    }

    @Test("unsupported locale reservation failure maps to unsupported locale")
    func unsupportedLocale() {
        let error = speechError(.cannotAllocateUnsupportedLocale)

        #expect(SpeechAnalyzerMapping.error(from: error, locale: locale) == .unsupportedLocale(locale))
    }

    @Test("missing or unreservable model assets map to model unavailable")
    func modelUnavailable() {
        let codes: [SFSpeechError.Code] = [.noModel, .assetLocaleNotAllocated, .tooManyAssetLocalesAllocated]

        for code in codes {
            #expect(SpeechAnalyzerMapping.error(from: speechError(code), locale: locale) == .modelUnavailable(locale))
        }
    }

    @Test("other errors map to recognition failure with their description")
    func otherErrors() {
        let error = speechError(.unexpectedAudioFormat)

        #expect(SpeechAnalyzerMapping.error(from: error, locale: locale) == .recognitionFailed("speech"))
    }
}

@Suite("SpeechAnalyzer transcript assembly")
struct SpeechAnalyzerTranscriptAssemblyTests {
    // Verified at runtime: consecutive final results carry their own leading space.
    @Test("final segments are concatenated in order and trimmed")
    func concatenatesSegments() {
        let transcript = SpeechAnalyzerMapping.transcript(fromFinalSegments: ["First one.", " Second one. ", "\n"])

        #expect(transcript == Transcript(text: "First one. Second one."))
    }

    @Test("no segments produce an empty transcript")
    func noSegments() {
        #expect(SpeechAnalyzerMapping.transcript(fromFinalSegments: []) == Transcript(text: ""))
    }
}
