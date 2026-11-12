import AVFoundation
import Foundation
import Synchronization

/// One recording's temporary audio file.
///
/// `append(_:)` may be called from the audio tap thread while the owner calls `finish()` or
/// `delete()` elsewhere; access is serialized by a lock and buffers are ignored once the file is closed.
/// A write failure is kept and reported by `finish()` so the tap never has to handle errors.
final class RecordingFile: Sendable {
    private static let namePrefix = "recording-"
    private static let fileExtension = "caf"

    let url: URL
    private let sampleRate: Double
    private let state: Mutex<State>

    private struct State {
        var file: AVAudioFile?
        var framesWritten: AVAudioFramePosition = 0
        var writeError: (any Error)?
    }

    /// Creates `directory` if needed and opens a new uniquely named CAF file in `format`.
    init(in directory: URL, format: AVAudioFormat) throws(AudioCaptureError) {
        let url = directory.appending(path: "\(Self.namePrefix)\(UUID().uuidString).\(Self.fileExtension)")
        let file: AVAudioFile
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            file = try AVAudioFile(
                forWriting: url,
                settings: format.settings,
                commonFormat: format.commonFormat,
                interleaved: format.isInterleaved
            )
        } catch {
            throw .storageFailed(String(describing: error))
        }
        self.url = url
        self.sampleRate = format.sampleRate
        self.state = Mutex(State(file: file))
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        state.withLock { state in
            guard let file = state.file, state.writeError == nil else { return }
            do {
                try file.write(from: buffer)
                state.framesWritten += AVAudioFramePosition(buffer.frameLength)
            } catch {
                state.writeError = error
            }
        }
    }

    /// Closes the file and returns it as captured audio, or throws the first write failure.
    /// The file is left on disk either way; the caller decides when to delete it.
    func finish() throws(AudioCaptureError) -> CapturedAudio {
        let (frames, writeError) = state.withLock { state in
            state.file?.close()
            state.file = nil
            return (state.framesWritten, state.writeError.map { String(describing: $0) })
        }
        if let writeError { throw .storageFailed(writeError) }
        return CapturedAudio(fileURL: url, duration: .seconds(Double(frames) / sampleRate))
    }

    /// Closes and removes the file. Safe to call more than once.
    func delete() {
        state.withLock { state in
            state.file?.close()
            state.file = nil
        }
        try? FileManager.default.removeItem(at: url)
    }

    /// Removes recording files in `directory` left behind by an earlier process (crash or force quit).
    /// Other files are left alone.
    static func removeLeftovers(in directory: URL) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasPrefix(namePrefix) && name.hasSuffix(".\(fileExtension)") {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
    }
}
