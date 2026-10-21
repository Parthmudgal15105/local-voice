import Foundation

// The recorder already writes mono 16-kHz PCM16 WAV. Read only completed PCM
// frames from that file; never rotate recorders or interrupt the microphone.
// If the writer's provisional header is unfamiliar, final batch recognition
// remains the fallback. Only finalized standalone chunks go to inference.
struct PCM16WaveLayout {
    let dataOffset: Int
    let sizeOffset: Int
    let declaredBytes: Int

    static func read(_ header: Data) -> PCM16WaveLayout? {
        func tag(_ start: Int) -> String {
            guard start + 4 <= header.count else { return "" }
            return String(decoding: header[start..<(start + 4)], as: UTF8.self)
        }
        func integer(_ start: Int, _ bytes: Int) -> Int {
            guard start + bytes <= header.count else { return -1 }
            return (0..<bytes).reduce(0) { $0 | (Int(header[start + $1]) << ($1 * 8)) }
        }
        guard header.count >= 12, tag(0) == "RIFF", tag(8) == "WAVE" else { return nil }
        var offset = 12, validFormat = false
        while offset + 8 <= header.count {
            let size = integer(offset + 4, 4)
            if tag(offset) == "fmt " {
                guard size >= 16, offset + 8 + size <= header.count else { return nil }
                let format = integer(offset + 8, 2)
                let isPCM = format == 1 || (format == 65534 && size >= 40 && integer(offset + 32, 2) == 1)
                validFormat = isPCM && integer(offset + 10, 2) == 1 && integer(offset + 12, 4) == 16000 && integer(offset + 22, 2) == 16
            }
            if tag(offset) == "data" {
                guard validFormat else { return nil }
                return PCM16WaveLayout(dataOffset: offset + 8, sizeOffset: offset + 4, declaredBytes: size)
            }
            guard size >= 0, size <= header.count, offset + 8 + size > offset else { return nil }
            offset += 8 + size + size % 2
        }
        return nil
    }

    static func wave(_ pcm: Data) -> Data {
        var header = Data()
        func number(_ value: UInt32, bytes: Int) {
            for byte in 0..<bytes { header.append(UInt8((value >> (byte * 8)) & 255)) }
        }
        header.append(Data("RIFF".utf8)); number(UInt32(36 + pcm.count), bytes: 4)
        header.append(Data("WAVEfmt ".utf8)); number(16, bytes: 4)
        number(1, bytes: 2); number(1, bytes: 2); number(16000, bytes: 4)
        number(32000, bytes: 4); number(2, bytes: 2); number(16, bytes: 2)
        header.append(Data("data".utf8)); number(UInt32(pcm.count), bytes: 4)
        header.append(pcm)
        return header
    }
}

struct LiveAudioChunker {
    struct Chunk { let pcm: Data; let overlapFrames: Int }
    private var pending = Data()
    private var overlap = 0
    mutating func append(_ bytes: Data) { pending.append(bytes) }

    mutating func take(final: Bool = false) -> [Chunk] {
        let windowFrames = 1600, minimum = 20 * 16000, maximum = 30 * 16000
        var chunks: [Chunk] = []
        while pending.count / 2 >= minimum {
            var quiet = 0, cut: Int?
            let available = min(maximum, pending.count / 2)
            for start in stride(from: minimum, through: max(minimum, available - windowFrames), by: windowFrames) {
                guard start + windowFrames <= pending.count / 2 else { break }
                var energy: Double = 0
                for frame in start..<(start + windowFrames) {
                    let bits = UInt16(pending[frame * 2]) | UInt16(pending[frame * 2 + 1]) << 8
                    let sample = Double(Int16(bitPattern: bits)) / 32768
                    energy += sample * sample
                }
                quiet = sqrt(energy / Double(windowFrames)) < 0.015 ? quiet + 1 : 0
                if quiet >= 4 { cut = start - windowFrames; break }
            }
            let forced = cut == nil
            if forced && pending.count / 2 < maximum { break }
            let boundary = cut ?? maximum
            chunks.append(Chunk(pcm: Data(pending.prefix(boundary * 2)), overlapFrames: overlap))
            // A forced cut may cross a word. Carry half a second forward;
            // reconciliation removes only exact multi-word boundary matches.
            let carry = forced ? 8000 : 0
            pending = Data(pending.dropFirst((boundary - carry) * 2)); overlap = carry
        }
        if final {
            if pending.count > overlap * 2 { chunks.append(Chunk(pcm: pending, overlapFrames: overlap)) }
            pending = Data(); overlap = 0
        }
        return chunks
    }
}

enum ChunkTranscriptJoiner {
    static func append(_ incoming: String, to previous: String, overlapping: Bool) -> String {
        guard !previous.isEmpty else { return incoming }
        guard overlapping, let regex = try? NSRegularExpression(pattern: "[\\p{L}\\p{M}\\p{N}]+") else { return previous + " " + incoming }
        func tokens(_ text: String) -> [(String, NSRange)] {
            regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
                guard let range = Range($0.range, in: text) else { return nil }
                return (String(text[range]).lowercased(), $0.range)
            }
        }
        let left = tokens(previous), right = tokens(incoming)
        let maximum = min(12, left.count, right.count)
        if maximum >= 2 {
            for count in stride(from: maximum, through: 2, by: -1) {
                if left.suffix(count).map(\.0) == right.prefix(count).map(\.0),
                   let last = Range(right[count - 1].1, in: incoming) {
                    let rest = incoming[last.upperBound...].drop(while: { $0.isWhitespace || ",.،，".contains($0) })
                    return rest.isEmpty ? previous : previous + " " + rest
                }
            }
        }
        return previous + " " + incoming
    }
}

final class LiveTranscriptionSession {
    let id: UUID
    private let audio: URL
    private let directory: URL
    private let tailQueue = DispatchQueue(label: "localvoice.live.audio", qos: .utility)
    private let recognitionQueue = DispatchQueue(label: "localvoice.live.recognition", qos: .userInitiated)
    private let lock = NSLock()
    private var cancelled = false
    private var activeJob: ProcessingJob?
    private var timer: DispatchSourceTimer?
    private var readOffset: UInt64?
    private var chunker = LiveAudioChunker()
    private var sequence = 0
    private var readerFailed = false // tailQueue only.
    private var failure = false // recognitionQueue only.
    private var text = ""
    private var completed = 0
    private var useRemote: Bool
    private var usedHome = false, usedMac = false, usedWhisper = false
    private var homeServerFailure: String?
    private let recognize: (URL, Bool, ProcessingJob) throws -> SpeechRecognitionResult
    private let progress: (String, String, Int) -> Void

    init(id: UUID = UUID(), audio: URL, preferHomeServer: Bool,
         recognize: @escaping (URL, Bool, ProcessingJob) throws -> SpeechRecognitionResult,
         progress: @escaping (String, String, Int) -> Void) throws {
        self.id = id; self.audio = audio; self.useRemote = preferHomeServer
        self.recognize = recognize; self.progress = progress
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("localvoice-live-" + id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    }

    private var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: tailQueue)
        timer.schedule(deadline: .now() + 0.25, repeating: 0.25)
        timer.setEventHandler { [weak self] in self?.readAvailable(final: false) }
        self.timer = timer; timer.resume()
    }

    private func readAvailable(final: Bool) {
        guard !isCancelled, !readerFailed else { return }
        do {
            let handle = try FileHandle(forReadingFrom: audio)
            defer { try? handle.close() }
            let header = try handle.read(upToCount: 65536) ?? Data()
            guard let layout = PCM16WaveLayout.read(header) else {
                if final { throw RecognitionFailure(message: "Live WAV layout unavailable.") }
                return // The recorder may not have flushed its header yet.
            }
            if readOffset == nil { readOffset = UInt64(layout.dataOffset) }
            let size = (try FileManager.default.attributesOfItem(atPath: audio.path)[.size] as? NSNumber)?.uint64Value ?? 0
            let end: UInt64
            if final {
                end = UInt64(layout.dataOffset) + UInt64(layout.declaredBytes)
                guard end <= size, end >= readOffset!, layout.declaredBytes % 2 == 0 else { throw RecognitionFailure(message: "Live audio coverage could not be verified.") }
            } else { end = size }
            guard end >= readOffset! else { throw RecognitionFailure(message: "The live recording changed unexpectedly.") }
            while end - readOffset! >= 2 {
                guard !isCancelled else { return }
                let count = min(128000, Int(end - readOffset!)) / 2 * 2
                try handle.seek(toOffset: readOffset!)
                let bytes = try handle.read(upToCount: count) ?? Data()
                guard bytes.count == count else { throw RecognitionFailure(message: "Could not read a complete live audio block.") }
                readOffset! += UInt64(bytes.count)
                chunker.append(bytes)
                for chunk in chunker.take() { try enqueue(chunk) }
            }
            if final { for chunk in chunker.take(final: true) { try enqueue(chunk) } }
        } catch {
            readerFailed = true
            progress("Live chunks unavailable · full recording will be processed when you finish", "", -1)
        }
    }

    private func enqueue(_ chunk: LiveAudioChunker.Chunk) throws {
        let url = directory.appendingPathComponent("part-\(sequence).wav"); sequence += 1
        try PCM16WaveLayout.wave(chunk.pcm).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        recognitionQueue.async { [self] in
            defer { try? FileManager.default.removeItem(at: url) }
            guard !isCancelled, !failure else { return }
            let job = ProcessingJob(timeout: useRemote ? 500 : 360)
            lock.lock()
            guard !cancelled else { lock.unlock(); return }
            activeJob = job; lock.unlock()
            defer { lock.lock(); if activeJob === job { activeJob = nil }; lock.unlock() }
            do {
                progress("Transcribing part \(completed + 1)…", text, completed)
                let result = try recognize(url, useRemote, job)
                try job.check()
                text = ChunkTranscriptJoiner.append(result.text, to: text, overlapping: chunk.overlapFrames > 0)
                usedHome = usedHome || result.usedHomeServer
                usedMac = usedMac || result.usedMacFallback
                usedWhisper = usedWhisper || result.usedWhisperFallback
                if result.usedMacFallback { useRemote = false }
                if let reason = result.homeServerFailure { homeServerFailure = reason }
                completed += 1
                progress("\(completed) part\(completed == 1 ? "" : "s") transcribed", text, completed)
            } catch {
                failure = true
                progress("Live transcription paused · full recording will be retried when you finish", text, completed)
            }
        }
    }

    // Call after AVAudioRecorder.stop(), when its final WAV header is on disk.
    func finish(completion: @escaping (SpeechRecognitionResult?, String) -> Void) {
        timer?.cancel(); timer = nil
        tailQueue.async { [self] in
            readAvailable(final: true)
            let readingFailed = readerFailed
            recognitionQueue.async { [self] in
                defer { try? FileManager.default.removeItem(at: directory) }
                guard !isCancelled else { return }
                let result = !readingFailed && !failure && !text.isEmpty
                    ? SpeechRecognitionResult(text: text, seconds: RecordingAudio.duration(of: audio), usedHomeServer: usedHome, usedMacFallback: usedMac, usedWhisperFallback: usedWhisper, homeServerFailure: homeServerFailure) : nil
                try? FileManager.default.removeItem(at: directory)
                completion(result, text)
            }
        }
    }

    func cancel() {
        lock.lock(); cancelled = true; let job = activeJob; lock.unlock()
        job?.cancel(); timer?.cancel(); timer = nil
        tailQueue.async { [self] in
            recognitionQueue.async { [self] in try? FileManager.default.removeItem(at: directory) }
        }
    }

    deinit { timer?.cancel() }
}
