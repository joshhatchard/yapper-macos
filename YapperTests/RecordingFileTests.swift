import AVFoundation
import Foundation
import Testing

@testable import Yapper

@Suite("RecordingFile")
struct RecordingFileTests {
    let directory = TemporaryDirectory()

    @Test("appended buffers are written and reported as the recording duration")
    func writesBuffers() throws {
        let format = TestAudio.format(sampleRate: 48_000, channels: 1)
        let file = try RecordingFile(in: directory.url, format: format)

        file.append(TestAudio.tone(format: format, seconds: 0.25))
        file.append(TestAudio.tone(format: format, seconds: 0.25))
        let audio = try file.finish()

        #expect(audio.fileURL == file.url)
        #expect(audio.duration == .seconds(0.5))
        let readBack = try AVAudioFile(forReading: audio.fileURL)
        #expect(readBack.length == 24_000)
        #expect(readBack.processingFormat.sampleRate == 48_000)
    }

    @Test("each recording gets its own file inside the recordings directory")
    func uniqueFiles() throws {
        let format = TestAudio.format(sampleRate: 16_000, channels: 1)

        let first = try RecordingFile(in: directory.url, format: format)
        let second = try RecordingFile(in: directory.url, format: format)

        #expect(first.url != second.url)
        #expect(first.url.deletingLastPathComponent() == directory.url)
        #expect(FileManager.default.fileExists(atPath: first.url.path))
    }

    @Test("a buffer the file cannot accept fails the recording when finished")
    func writeFailure() throws {
        let file = try RecordingFile(in: directory.url, format: TestAudio.format(sampleRate: 48_000, channels: 1))

        file.append(TestAudio.tone(format: TestAudio.format(sampleRate: 44_100, channels: 2), seconds: 0.1))

        #expect {
            try file.finish()
        } throws: { error in
            guard case .storageFailed = error as? AudioCaptureError else { return false }
            return true
        }
    }

    @Test("an unusable directory fails as a storage error")
    func unusableDirectory() throws {
        let notADirectory = directory.url.appending(path: "plain-file")
        try Data().write(to: notADirectory)

        #expect {
            try RecordingFile(in: notADirectory, format: TestAudio.format(sampleRate: 16_000, channels: 1))
        } throws: { error in
            guard case .storageFailed = error as? AudioCaptureError else { return false }
            return true
        }
    }

    @Test("delete removes the file and ignores later buffers")
    func delete() throws {
        let format = TestAudio.format(sampleRate: 16_000, channels: 1)
        let file = try RecordingFile(in: directory.url, format: format)

        file.delete()
        file.append(TestAudio.tone(format: format, seconds: 0.1))

        #expect(!FileManager.default.fileExists(atPath: file.url.path))
    }
}
