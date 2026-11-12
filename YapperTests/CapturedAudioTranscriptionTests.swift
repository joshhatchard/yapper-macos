import AVFoundation
import Foundation
import Testing

@testable import Yapper

/// Integration: a recording produced by `MicrophoneCapture` from microphone-shaped buffers
/// (48 kHz, 2-channel deinterleaved Float32, 4096-frame chunks) is accepted by the real on-device
/// transcriber. The buffers come from locally synthesized speech; no microphone is used.
@Suite("Captured audio transcription (on-device integration, no microphone)")
struct CapturedAudioTranscriptionTests {
    static let locale = Locale(identifier: "en_US")

    @Test(
        "speech delivered through capture is transcribed from the temporary file",
        .enabled("locale assets already installed") { await SpeechTestEnvironment.isInstalled(locale) },
        .timeLimit(.minutes(1))
    )
    func captureThenTranscribe() async throws {
        let directory = TemporaryDirectory()
        let input = FakeAudioInput()
        let micFormat = TestAudio.format(sampleRate: 48_000, channels: 2)
        input.configure { $0.format = micFormat }
        let capture = MicrophoneCapture(
            authorization: FixedMicrophoneAuthorization(),
            input: input,
            recordingsDirectory: directory.url
        )
        let speech = try SyntheticAudio.speech("The quick brown fox jumps over the lazy dog.")
        defer { try? FileManager.default.removeItem(at: speech.fileURL) }

        try await capture.startCapture()
        for buffer in try TestAudio.chunks(of: speech.fileURL, convertedTo: micFormat, frames: 4_096) {
            input.deliver(buffer)
        }
        let audio = try await capture.stopCapture()
        let transcript = try await SpeechAnalyzerTranscriber().transcribe(audio, locale: Self.locale)
        await capture.discard(audio)

        #expect(transcript.text.lowercased().contains("quick brown fox"))
        #expect(directory.fileNames.isEmpty)
    }
}
