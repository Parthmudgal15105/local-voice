import Foundation
import AVFoundation

struct RecordingAudio {
    struct Window {
        let start: AVAudioFramePosition
        let frames: AVAudioFrameCount
        let rms: Float
    }
    let frames: AVAudioFramePosition
    let sampleRate: Double
    let peak: Float
    let windows: [Window]
    var seconds: Double { Double(frames) / sampleRate }

    static func duration(of url: URL) -> Double {
        guard let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0 else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    static func inspect(_ url: URL, job: ProcessingJob) throws -> RecordingAudio {
        try job.check()
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url) }
        catch { throw RecognitionFailure(message: "The recording could not be read. The original audio is available in recovery.") }
        guard file.processingFormat.channelCount == 1, file.processingFormat.sampleRate == 16000 else {
            throw RecognitionFailure(message: "The recording must be mono 16 kHz audio.")
        }
        guard file.length > 0 else { throw RecognitionFailure(message: "The recording contains no audio frames. Check your microphone.") }
        let capacity: AVAudioFrameCount = 1600 // 100 ms; also finds quiet cuts.
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: capacity) else {
            throw RecognitionFailure(message: "Could not allocate an audio buffer.")
        }
        var windows: [Window] = [], peak: Float = 0
        var consumed: AVAudioFramePosition = 0
        while consumed < file.length {
            try job.check()
            try file.read(into: buffer, frameCount: min(capacity, AVAudioFrameCount(min(file.length - consumed, Int64(capacity)))))
            guard buffer.frameLength > 0, let samples = buffer.floatChannelData?[0] else {
                throw RecognitionFailure(message: "The recording ended before all its audio could be read.")
            }
            var squares: Double = 0
            for index in 0..<Int(buffer.frameLength) {
                let value = samples[index]
                guard value.isFinite else { throw RecognitionFailure(message: "The recording contains invalid audio samples.") }
                peak = max(peak, abs(value)); squares += Double(value) * Double(value)
            }
            windows.append(Window(start: consumed, frames: buffer.frameLength, rms: Float(sqrt(squares / Double(buffer.frameLength)))))
            consumed += Int64(buffer.frameLength)
        }
        // Reject digital silence, not a short word or a quiet microphone.
        guard peak > 1 / 32768 else { throw RecognitionFailure(message: "The recording is silent. Check your microphone and input device.") }
        return RecordingAudio(frames: consumed, sampleRate: file.processingFormat.sampleRate, peak: peak, windows: windows)
    }

    // Handy selects chunking from the model's capabilities. Here all long
    // dictations use ~30-second chunks so Qwen, HP, and the CLI see the same
    // bounded input. Cuts prefer quiet 100-ms windows within five seconds.
    var ranges: [Range<AVAudioFramePosition>] {
        guard seconds > 40 else { return [0..<frames] }
        let target = Int64(sampleRate * 30), radius = Int64(sampleRate * 5)
        var result: [Range<AVAudioFramePosition>] = [], start: Int64 = 0
        while frames - start > Int64(sampleRate * 40) {
            let ideal = start + target
            let candidates = windows.filter { $0.start >= ideal - radius && $0.start <= ideal + radius }
            let quiet = candidates.filter { $0.rms < 0.015 }.min {
                if abs($0.rms - $1.rms) < 0.0001 { return abs($0.start - ideal) < abs($1.start - ideal) }
                return $0.rms < $1.rms
            }
            let end = quiet.map { $0.start + Int64($0.frames / 2) } ?? ideal
            result.append(start..<end); start = end
        }
        if start < frames { result.append(start..<frames) }
        return result
    }

    func write(_ range: Range<AVAudioFramePosition>, from source: URL, to destination: URL, job: ProcessingJob) throws {
        let file = try AVAudioFile(forReading: source)
        file.framePosition = range.lowerBound
        guard FileManager.default.createFile(atPath: destination.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw RecognitionFailure(message: "Could not create a private audio chunk.")
        }
        let output = try AVAudioFile(forWriting: destination, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false])
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096) else {
            throw RecognitionFailure(message: "Could not allocate an audio chunk buffer.")
        }
        var remaining = range.upperBound - range.lowerBound
        while remaining > 0 {
            try job.check()
            try file.read(into: buffer, frameCount: AVAudioFrameCount(min(4096, remaining)))
            guard buffer.frameLength > 0 else { throw RecognitionFailure(message: "An audio chunk could not be read completely.") }
            try output.write(from: buffer)
            remaining -= Int64(buffer.frameLength)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }
}
