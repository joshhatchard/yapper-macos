import AVFoundation
import Foundation
import Speech
import Testing

@testable import Yapper

/// Integration checks against the real on-device Speech framework.
/// They never download model assets: tests that need a model run only when the
/// locale is already installed on this Mac, and audio is synthesized locally with `say`.
@Suite("SpeechAnalyzerTranscriber (on-device integration)")
struct SpeechAnalyzerTranscriberTests {
    static let installedLocale = Locale(identifier: "en_US")
    static let unsupportedLocale = Locale(identifier: "xx_YY")

    let transcriber = SpeechAnalyzerTranscriber()

    @Test("a locale the framework does not support reports unsupported")
    func unsupportedAvailability() async {
        #expect(await transcriber.availability(for: Self.unsupportedLocale) == .unsupportedLocale)
    }

    @Test(
        "an installed locale reports ready",
        .enabled("locale assets already installed") { await SpeechTestEnvironment.isInstalled(installedLocale) }
    )
    func installedAvailability() async {
        #expect(await transcriber.availability(for: Self.installedLocale) == .ready)
    }

    @Test("prepare rejects an unsupported locale")
    func prepareUnsupported() async {
        await #expect(throws: TranscriptionError.unsupportedLocale(Self.unsupportedLocale)) {
            try await transcriber.prepare(for: Self.unsupportedLocale)
        }
    }

    @Test(
        "prepare succeeds without downloading when the locale is already installed",
        .enabled("locale assets already installed") { await SpeechTestEnvironment.isInstalled(installedLocale) }
    )
    func prepareInstalled() async throws {
        try await transcriber.prepare(for: Self.installedLocale)

        #expect(await transcriber.availability(for: Self.installedLocale) == .ready)
    }

    @Test("transcribe rejects an unsupported locale")
    func transcribeUnsupported() async throws {
        let audio = try SyntheticAudio.silence(seconds: 0)

        await #expect(throws: TranscriptionError.unsupportedLocale(Self.unsupportedLocale)) {
            try await transcriber.transcribe(audio, locale: Self.unsupportedLocale)
        }
    }

    @Test(
        "transcribe never downloads: a supported but uninstalled locale fails as model unavailable",
        .enabled("some supported locale is not installed") {
            await SpeechTestEnvironment.supportedButNotInstalledLocale() != nil
        }
    )
    func transcribeUninstalledLocale() async throws {
        let locale = try #require(await SpeechTestEnvironment.supportedButNotInstalledLocale())
        let audio = try SyntheticAudio.silence(seconds: 0)

        await #expect(throws: TranscriptionError.modelUnavailable(locale)) {
            try await transcriber.transcribe(audio, locale: locale)
        }
        #expect(!(await SpeechTestEnvironment.isInstalled(locale)))
    }

    @Test(
        "unreadable audio fails as recognition failure",
        .enabled("locale assets already installed") { await SpeechTestEnvironment.isInstalled(installedLocale) }
    )
    func transcribeMissingFile() async {
        let audio = CapturedAudio(
            fileURL: FileManager.default.temporaryDirectory.appending(path: "missing-\(UUID()).wav"),
            duration: .zero
        )

        await #expect {
            try await transcriber.transcribe(audio, locale: Self.installedLocale)
        } throws: { error in
            guard case .recognitionFailed = error as? TranscriptionError else { return false }
            return true
        }
    }

    // A naive analyzeSequence + cancelAndFinishNow on a zero-frame file never ends the results
    // sequence (verified hang on macOS 26.6.2). The adapter must return instead.
    @Test(
        "zero-length audio returns an empty transcript without hanging",
        .enabled("locale assets already installed") { await SpeechTestEnvironment.isInstalled(installedLocale) },
        .timeLimit(.minutes(1))
    )
    func transcribeEmptyAudio() async throws {
        let audio = try SyntheticAudio.silence(seconds: 0)

        #expect(try await transcriber.transcribe(audio, locale: Self.installedLocale) == Transcript(text: ""))
    }

    @Test(
        "silent audio returns an empty transcript",
        .enabled("locale assets already installed") { await SpeechTestEnvironment.isInstalled(installedLocale) },
        .timeLimit(.minutes(1))
    )
    func transcribeSilence() async throws {
        let audio = try SyntheticAudio.silence(seconds: 2)

        #expect(try await transcriber.transcribe(audio, locale: Self.installedLocale) == Transcript(text: ""))
    }

    @Test(
        "locally synthesized speech is transcribed on device",
        .enabled("locale assets already installed") { await SpeechTestEnvironment.isInstalled(installedLocale) },
        .timeLimit(.minutes(1))
    )
    func transcribeSyntheticSpeech() async throws {
        let audio = try SyntheticAudio.speech("The quick brown fox jumps over the lazy dog.")

        let transcript = try await transcriber.transcribe(audio, locale: Self.installedLocale)

        #expect(transcript.text.lowercased().contains("quick brown fox"))
    }

    @Test(
        "cancelling the calling task stops analysis and throws cancelled",
        .enabled("locale assets already installed") { await SpeechTestEnvironment.isInstalled(installedLocale) },
        .timeLimit(.minutes(1))
    )
    func transcribeCancellation() async throws {
        let sentence = "This is a long synthetic dictation sample used to exercise cancellation. "
        let audio = try SyntheticAudio.speech(String(repeating: sentence, count: 15))
        let transcriber = self.transcriber
        let task = Task { try await transcriber.transcribe(audio, locale: Self.installedLocale) }

        try await Task.sleep(for: .milliseconds(500))
        let cancelledAt = ContinuousClock.now
        task.cancel()

        await #expect(throws: TranscriptionError.cancelled) { try await task.value }
        // Full analysis of this ~60 s sample takes ~2 s; cancellation must cut it short.
        #expect(ContinuousClock.now - cancelledAt < .milliseconds(750))
    }
}

enum SpeechTestEnvironment {
    static func isInstalled(_ locale: Locale) async -> Bool {
        let wanted = locale.identifier(.bcp47)
        return await SpeechTranscriber.installedLocales.contains { $0.identifier(.bcp47) == wanted }
    }

    static func supportedButNotInstalledLocale() async -> Locale? {
        let installed = Set(await SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) })
        return await SpeechTranscriber.supportedLocales
            .sorted { $0.identifier < $1.identifier }
            .first { !installed.contains($0.identifier(.bcp47)) }
    }
}

/// Local, synthetic audio fixtures. Nothing is recorded from the microphone or fetched remotely.
enum SyntheticAudio {
    static func silence(seconds: Double) throws -> CapturedAudio {
        let url = FileManager.default.temporaryDirectory.appending(path: "yapper-silence-\(UUID()).wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let frames = AVAudioFrameCount(seconds * format.sampleRate)
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            if frames > 0 {
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
                buffer.frameLength = frames
                try file.write(from: buffer)
            }
        }
        return CapturedAudio(fileURL: url, duration: .seconds(seconds))
    }

    static func speech(_ text: String) throws -> CapturedAudio {
        let url = FileManager.default.temporaryDirectory.appending(path: "yapper-speech-\(UUID()).aiff")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", url.path, text]
        try say.run()
        say.waitUntilExit()
        guard say.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
        let file = try AVAudioFile(forReading: url)
        return CapturedAudio(fileURL: url, duration: .seconds(Double(file.length) / file.processingFormat.sampleRate))
    }
}
