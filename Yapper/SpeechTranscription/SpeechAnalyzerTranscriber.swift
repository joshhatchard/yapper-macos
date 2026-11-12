import AVFoundation
import Foundation
import Speech

/// On-device transcription via SpeechAnalyzer + SpeechTranscriber (macOS 26+).
///
/// Audio is analyzed locally. Model assets are managed by the system (`AssetInventory`) and may
/// need a one-time download from Apple; only `prepare(for:)` ever starts that download.
actor SpeechAnalyzerTranscriber: SpeechTranscribing {
    init() {}

    func availability(for locale: Locale) async -> TranscriptionAvailability {
        guard SpeechTranscriber.isAvailable else { return .unavailable }
        guard let resolved = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            return .unsupportedLocale
        }
        let status = await AssetInventory.status(forModules: [Self.makeModule(locale: resolved)])
        return SpeechAnalyzerMapping.availability(
            serviceAvailable: true,
            assetStatus: status,
            localeInstalled: await Self.isInstalled(resolved)
        )
    }

    /// Installs model assets for `locale` if needed. This can download from Apple's servers,
    /// so call it only after the user has opted in.
    func prepare(for locale: Locale) async throws(TranscriptionError) {
        switch await availability(for: locale) {
        case .ready:
            return
        case .unsupportedLocale:
            throw .unsupportedLocale(locale)
        case .unavailable:
            throw .modelUnavailable(locale)
        case .modelNotInstalled:
            break
        }
        guard let resolved = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw .unsupportedLocale(locale)
        }
        do {
            let module = Self.makeModule(locale: resolved)
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                try await request.downloadAndInstall()
            }
        } catch {
            throw SpeechAnalyzerMapping.error(from: error, locale: locale)
        }
        guard await availability(for: locale) == .ready else { throw .modelUnavailable(locale) }
    }

    /// Transcribes a finished recording. Never downloads assets: an uninstalled model fails with
    /// `.modelUnavailable`. Cancelling the calling task stops analysis and throws `.cancelled`.
    func transcribe(_ audio: CapturedAudio, locale: Locale) async throws(TranscriptionError) -> Transcript {
        if Task.isCancelled { throw .cancelled }
        switch await availability(for: locale) {
        case .ready:
            break
        case .unsupportedLocale:
            throw .unsupportedLocale(locale)
        case .modelNotInstalled, .unavailable:
            throw .modelUnavailable(locale)
        }
        guard let resolved = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw .unsupportedLocale(locale)
        }
        do {
            return try await Self.analyze(fileURL: audio.fileURL, locale: resolved)
        } catch {
            throw SpeechAnalyzerMapping.error(from: error, locale: locale)
        }
    }

    private static func analyze(fileURL: URL, locale: Locale) async throws -> Transcript {
        let file = try AVAudioFile(forReading: fileURL)
        // A zero-frame file never terminates the results sequence (verified on macOS 26.6.2).
        guard file.length > 0 else { return Transcript(text: "") }

        let module = makeModule(locale: locale)
        let results = module.results
        let analyzer = SpeechAnalyzer(modules: [module])
        let collector = Task {
            var segments: [String] = []
            for try await result in results where result.isFinal {
                segments.append(String(result.text.characters))
            }
            return segments
        }

        // SpeechAnalyzer does not observe task cancellation on its own (verified), so forward it.
        return try await withTaskCancellationHandler {
            do {
                if let end = try await analyzer.analyzeSequence(from: file) {
                    try Task.checkCancellation()
                    try await analyzer.finalizeAndFinish(through: end)
                } else {
                    await analyzer.cancelAndFinishNow()
                    collector.cancel()
                    return Transcript(text: "")
                }
                let segments = try await collector.value
                try Task.checkCancellation()
                return SpeechAnalyzerMapping.transcript(fromFinalSegments: segments)
            } catch {
                await analyzer.cancelAndFinishNow()
                collector.cancel()
                throw Task.isCancelled ? CancellationError() : error
            }
        } onCancel: {
            collector.cancel()
            Task { await analyzer.cancelAndFinishNow() }
        }
    }

    /// Final results only: no volatile results, alternatives, or timing attributes.
    private static func makeModule(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
    }

    private static func isInstalled(_ locale: Locale) async -> Bool {
        let wanted = locale.identifier(.bcp47)
        return await SpeechTranscriber.installedLocales.contains { $0.identifier(.bcp47) == wanted }
    }
}
