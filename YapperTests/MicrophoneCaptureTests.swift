import AVFoundation
import Foundation
import Testing

@testable import Yapper

/// Capture lifecycle and resource ownership, with a fake microphone input.
/// No test here touches audio hardware or microphone permission.
@Suite("MicrophoneCapture lifecycle")
struct MicrophoneCaptureTests {
    let directory = TemporaryDirectory()
    let input = FakeAudioInput()

    func makeCapture(permission: PermissionStatus = .authorized) -> MicrophoneCapture {
        MicrophoneCapture(
            authorization: FixedMicrophoneAuthorization(current: permission),
            input: input,
            recordingsDirectory: directory.url
        )
    }

    @Test("stop returns the delivered audio as a temporary file and releases the input")
    func recordsUntilStopped() async throws {
        let capture = makeCapture()

        try await capture.startCapture()
        #expect(input.snapshot.isRunning)
        input.deliver(TestAudio.tone(format: input.snapshot.format, seconds: 0.5))
        let audio = try await capture.stopCapture()

        #expect(!input.snapshot.isRunning)
        #expect(audio.duration == .seconds(0.5))
        #expect(directory.fileNames == [audio.fileURL.lastPathComponent])
        #expect(try AVAudioFile(forReading: audio.fileURL).length == 24_000)
    }

    @Test("starting while already capturing fails and keeps the current recording")
    func startWhileCapturing() async throws {
        let capture = makeCapture()
        try await capture.startCapture()

        await #expect(throws: AudioCaptureError.alreadyCapturing) { try await capture.startCapture() }

        #expect(input.snapshot.prepareCount == 1)
        #expect(input.snapshot.isRunning)
        #expect(directory.fileNames.count == 1)
    }

    @Test(
        "capture never opens the input without microphone authorization",
        arguments: [PermissionStatus.notDetermined, .denied, .restricted]
    )
    func requiresAuthorization(permission: PermissionStatus) async {
        let capture = makeCapture(permission: permission)

        await #expect(throws: AudioCaptureError.permissionDenied) { try await capture.startCapture() }

        #expect(input.snapshot.prepareCount == 0)
        #expect(directory.fileNames.isEmpty)
    }

    @Test("a missing input device fails before any file is created")
    func noInputDevice() async {
        input.configure { $0.prepareError = .noInputDevice }
        let capture = makeCapture()

        await #expect(throws: AudioCaptureError.noInputDevice) { try await capture.startCapture() }

        #expect(directory.fileNames.isEmpty)
    }

    @Test("an input that fails to start is released and its file removed")
    func inputStartFailure() async throws {
        input.configure { $0.startError = .engineFailed("start failed") }
        let capture = makeCapture()

        await #expect(throws: AudioCaptureError.engineFailed("start failed")) { try await capture.startCapture() }

        #expect(input.snapshot.stopCount == 1)
        #expect(directory.fileNames.isEmpty)
        input.configure { $0.startError = nil }
        try await capture.startCapture()
    }

    @Test("a recording file that cannot be created releases the prepared input")
    func storageFailureOnStart() async throws {
        let blocked = directory.url.appending(path: "blocked")
        try Data().write(to: blocked)
        let capture = MicrophoneCapture(
            authorization: FixedMicrophoneAuthorization(),
            input: input,
            recordingsDirectory: blocked
        )

        await #expect {
            try await capture.startCapture()
        } throws: { error in
            guard case .storageFailed = error as? AudioCaptureError else { return false }
            return true
        }
        #expect(input.snapshot.stopCount == 1)
    }

    @Test("stopping without an active capture fails")
    func stopWhileIdle() async {
        let capture = makeCapture()

        await #expect(throws: AudioCaptureError.notCapturing) { try await capture.stopCapture() }
    }

    @Test("a write failure during recording surfaces on stop and leaves nothing behind")
    func writeFailureOnStop() async throws {
        let capture = makeCapture()
        try await capture.startCapture()
        input.deliver(TestAudio.tone(format: TestAudio.format(sampleRate: 44_100, channels: 2), seconds: 0.1))

        await #expect {
            try await capture.stopCapture()
        } throws: { error in
            guard case .storageFailed = error as? AudioCaptureError else { return false }
            return true
        }

        #expect(!input.snapshot.isRunning)
        #expect(directory.fileNames.isEmpty)
        try await capture.startCapture()
    }

    @Test("cancel releases the input and deletes the partial recording")
    func cancel() async throws {
        let capture = makeCapture()
        try await capture.startCapture()
        input.deliver(TestAudio.tone(format: input.snapshot.format, seconds: 0.2))

        await capture.cancelCapture()

        #expect(!input.snapshot.isRunning)
        #expect(directory.fileNames.isEmpty)
        await #expect(throws: AudioCaptureError.notCapturing) { try await capture.stopCapture() }
        try await capture.startCapture()
    }

    @Test("cancel without an active capture does nothing")
    func cancelWhileIdle() async {
        let capture = makeCapture()

        await capture.cancelCapture()

        #expect(input.snapshot.stopCount == 0)
    }

    @Test("discard deletes a finished recording")
    func discard() async throws {
        let capture = makeCapture()
        try await capture.startCapture()
        let audio = try await capture.stopCapture()

        await capture.discard(audio)

        #expect(directory.fileNames.isEmpty)
    }

    @Test("discard leaves files this capture did not record")
    func discardForeignFile() async throws {
        let foreign = directory.url.appending(path: "user-file.caf")
        try Data([1, 2, 3]).write(to: foreign)
        let capture = makeCapture()

        await capture.discard(CapturedAudio(fileURL: foreign, duration: .seconds(1)))

        #expect(FileManager.default.fileExists(atPath: foreign.path))
    }

    @Test("consecutive sessions each produce their own file")
    func consecutiveSessions() async throws {
        let capture = makeCapture()

        try await capture.startCapture()
        let first = try await capture.stopCapture()
        try await capture.startCapture()
        let second = try await capture.stopCapture()

        #expect(first.fileURL != second.fileURL)
        #expect(directory.fileNames.count == 2)
    }

    @Test("recordings default to an app-owned folder in the per-user temporary directory")
    func defaultDirectory() {
        let directory = MicrophoneCapture.defaultRecordingsDirectory

        #expect(directory.deletingLastPathComponent() == FileManager.default.temporaryDirectory)
        #expect(directory.lastPathComponent == "Yapper-Recordings")
    }

    @Test("recordings left by an earlier run are removed when capture is created")
    func removesLeftovers() throws {
        let leftover = directory.url.appending(path: "recording-\(UUID().uuidString).caf")
        let unrelated = directory.url.appending(path: "notes.txt")
        try Data([0]).write(to: leftover)
        try Data([0]).write(to: unrelated)

        _ = makeCapture()

        #expect(directory.fileNames == ["notes.txt"])
    }
}
