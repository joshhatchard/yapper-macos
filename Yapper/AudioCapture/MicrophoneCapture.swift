import Foundation

/// Records the microphone to a temporary file, one session at a time.
///
/// Every file it creates is deleted on cancel, on any start/stop failure, or when the finished
/// recording is passed to `discard(_:)`. Files orphaned by a crash are removed on the next launch.
/// No method shows the permission prompt except `requestPermission()`.
actor MicrophoneCapture: AudioCapturing {
    private let authorization: any MicrophoneAuthorizing
    private let input: any AudioInputSource
    private let recordingsDirectory: URL
    private var recording: RecordingFile?
    private var finished: Set<URL> = []

    /// Per-user temporary folder (`$TMPDIR`) owned by the app, used only for in-flight recordings.
    static let defaultRecordingsDirectory = FileManager.default.temporaryDirectory
        .appending(path: "Yapper-Recordings", directoryHint: .isDirectory)

    init(
        authorization: any MicrophoneAuthorizing = SystemMicrophoneAuthorization(),
        input: any AudioInputSource = AudioEngineInput(),
        recordingsDirectory: URL = MicrophoneCapture.defaultRecordingsDirectory
    ) {
        self.authorization = authorization
        self.input = input
        self.recordingsDirectory = recordingsDirectory
        RecordingFile.removeLeftovers(in: recordingsDirectory)
    }

    func permissionStatus() async -> PermissionStatus {
        authorization.status()
    }

    func requestPermission() async -> PermissionStatus {
        await authorization.request()
    }

    /// Fails with `.permissionDenied` unless already authorized (including not-yet-asked),
    /// so the system prompt never appears in the middle of a shortcut press.
    func startCapture() async throws(AudioCaptureError) {
        guard recording == nil else { throw .alreadyCapturing }
        guard authorization.status() == .authorized else { throw .permissionDenied }
        let format = try input.prepare()
        let file: RecordingFile
        do {
            file = try RecordingFile(in: recordingsDirectory, format: format)
        } catch {
            input.stop()
            throw error
        }
        do {
            try input.start { file.append($0) }
        } catch {
            input.stop()
            file.delete()
            throw error
        }
        recording = file
    }

    /// Ends the session. The input is released whether or not this throws.
    func stopCapture() async throws(AudioCaptureError) -> CapturedAudio {
        guard let file = recording else { throw .notCapturing }
        recording = nil
        input.stop()
        do {
            let audio = try file.finish()
            finished.insert(audio.fileURL)
            return audio
        } catch {
            file.delete()
            throw error
        }
    }

    func cancelCapture() async {
        guard let file = recording else { return }
        recording = nil
        input.stop()
        file.delete()
    }

    /// Deletes a recording returned by `stopCapture()`. Files this capture did not create are ignored.
    func discard(_ audio: CapturedAudio) async {
        guard finished.remove(audio.fileURL) != nil else { return }
        try? FileManager.default.removeItem(at: audio.fileURL)
    }
}
