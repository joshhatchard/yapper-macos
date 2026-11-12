import AVFoundation
import Foundation
import Testing

@testable import Yapper

/// Real microphone checks. Skipped unless the user opts in, because they show the macOS microphone
/// prompt (first run) and record from the default input device:
///
///     TEST_RUNNER_YAPPER_MICROPHONE_TESTS=1 xcodebuild test ... \
///         -only-testing:YapperTests/MicrophoneHardwareTests
///
/// `speakerLoopback` plays synthesized speech through the speakers; run it in a quiet room with
/// the volume up. Audio stays in a temporary directory that the test deletes.
@Suite(
    "Microphone hardware (opt-in, records from the default input)",
    .enabled(if: ProcessInfo.processInfo.environment["YAPPER_MICROPHONE_TESTS"] == "1"),
    .serialized
)
struct MicrophoneHardwareTests {
    let directory = TemporaryDirectory()

    func makeCapture() async throws -> MicrophoneCapture {
        let authorization = SystemMicrophoneAuthorization()
        try #require(await authorization.request() == .authorized, "grant microphone access to Yapper")
        return MicrophoneCapture(
            authorization: authorization, input: AudioEngineInput(), recordingsDirectory: directory.url)
    }

    @Test("the default input device records for as long as capture runs", .timeLimit(.minutes(1)))
    func recordsFromDefaultInput() async throws {
        let capture = try await makeCapture()

        try await capture.startCapture()
        try await Task.sleep(for: .seconds(1))
        let audio = try await capture.stopCapture()

        #expect(audio.duration > .milliseconds(800))
        #expect(audio.duration < .milliseconds(1_500))
        await capture.discard(audio)
        #expect(directory.fileNames.isEmpty)
    }

    @Test("speech played through the speakers is captured and transcribed", .timeLimit(.minutes(1)))
    func speakerLoopback() async throws {
        let capture = try await makeCapture()

        try await capture.startCapture()
        try SpeakerOutput.say("The quick brown fox jumps over the lazy dog.")
        let audio = try await capture.stopCapture()
        let transcript = try await SpeechAnalyzerTranscriber().transcribe(audio, locale: Locale(identifier: "en_US"))
        await capture.discard(audio)

        #expect(transcript.text.lowercased().contains("brown fox"), "heard: \(transcript.text)")
    }
}

private enum SpeakerOutput {
    /// Speaks `text` aloud and returns when playback has finished.
    static func say(_ text: String) throws {
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = [text]
        try say.run()
        say.waitUntilExit()
    }
}
