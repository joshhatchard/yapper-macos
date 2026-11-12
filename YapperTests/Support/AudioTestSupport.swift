import AVFoundation
import Foundation

/// A unique, self-deleting temporary directory for one test.
final class TemporaryDirectory {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory.appending(
            path: "yapper-tests-\(UUID())", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// Names of the files currently in the directory, sorted.
    var fileNames: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
    }
}

/// Generated PCM buffers. Nothing here touches the microphone.
enum TestAudio {
    /// Deinterleaved Float32, the format AVAudioEngine's input node delivers.
    static func format(sampleRate: Double, channels: AVAudioChannelCount) -> AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
    }

    static func tone(format: AVAudioFormat, seconds: Double, frequency: Double = 440) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(seconds * format.sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(format.channelCount) {
            let samples = buffer.floatChannelData![channel]
            for frame in 0..<Int(frames) {
                samples[frame] = Float(0.2 * sin(2 * .pi * frequency * Double(frame) / format.sampleRate))
            }
        }
        return buffer
    }

    /// Reads `url`, converts it to `format`, and splits it into buffers of at most `frames` frames.
    static func chunks(of url: URL, convertedTo format: AVAudioFormat, frames: AVAudioFrameCount) throws
        -> [AVAudioPCMBuffer]
    {
        let file = try AVAudioFile(forReading: url)
        let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: source)
        let converter = AVAudioConverter(from: file.processingFormat, to: format)!
        let ratio = format.sampleRate / file.processingFormat.sampleRate
        let converted = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(Double(source.frameLength) * ratio) + frames
        )!
        nonisolated(unsafe) var consumed = false
        var conversionError: NSError?
        converter.convert(to: converted, error: &conversionError) { _, status in
            status.pointee = consumed ? .endOfStream : .haveData
            defer { consumed = true }
            return consumed ? nil : source
        }
        if let conversionError { throw conversionError }

        return stride(from: 0, to: converted.frameLength, by: Int(frames)).map { start in
            let count = min(frames, converted.frameLength - start)
            let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
            chunk.frameLength = count
            for channel in 0..<Int(format.channelCount) {
                chunk.floatChannelData![channel].update(
                    from: converted.floatChannelData![channel].advanced(by: Int(start)),
                    count: Int(count)
                )
            }
            return chunk
        }
    }
}
