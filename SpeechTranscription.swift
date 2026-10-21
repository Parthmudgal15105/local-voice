import Foundation

struct SpeechRecognitionResult {
    let text: String
    let seconds: Double
    let usedHomeServer: Bool
    let usedMacFallback: Bool
    let usedWhisperFallback: Bool
    var homeServerFailure: String? = nil
}

enum SpeechTranscription {
    static func recognize(audio: URL, data: URL, model: URL, vad: URL, translate: Bool, vocabulary: [String],
                          homeServerModel: String?, engine: SpeechEngine, job: ProcessingJob,
                          progress: @escaping (String, String) -> Void) throws -> SpeechRecognitionResult {
        try run(audio: audio, vocabulary: vocabulary, preferHomeServer: homeServerModel != nil, job: job, recognize: { input, remote in
            try job.check()
            guard !engine.isStopped else { throw CancellationError() }
            return try engine.transcribe(audio: input, model: model, vad: vad, translate: translate, vocabulary: vocabulary, homeServerModel: remote ? homeServerModel : nil, job: job)
        }, whisperFallback: { input in
            guard !engine.isStopped else { throw CancellationError() }
            return try whisperFallback(tryHelper: model.lastPathComponent.hasPrefix("Qwen3-ASR"), job: job, helper: {
                try engine.transcribe(audio: input, model: AppResources.asset("ggml-large-v3.bin", userDirectory: data), vad: vad, translate: translate, vocabulary: vocabulary, job: job)
            }, cli: {
                try job.check()
                guard !engine.isStopped else { throw CancellationError() }
                progress("Trying direct Whisper fallback…", "")
                return try whisperCLI(audio: input, data: data, translate: translate, vocabulary: vocabulary, job: job)
            })
        }, progress: progress)
    }

    // A failed Qwen helper can still use the independent Whisper helper.
    // If that cannot run, the CLI bypasses the HTTP/helper layer entirely.
    static func whisperFallback(tryHelper: Bool, job: ProcessingJob,
                                helper: () throws -> String, cli: () throws -> String) throws -> String {
        try job.check()
        if tryHelper {
            do { return try helper() }
            catch { try job.check() }
        }
        return try cli()
    }

    static func run(audio url: URL, vocabulary: [String], preferHomeServer: Bool, job: ProcessingJob,
                    recognize: (URL, Bool) throws -> String,
                    whisperFallback: (URL) throws -> String,
                    progress: (String, String) -> Void) throws -> SpeechRecognitionResult {
        progress("Checking recording…", "")
        let audio = try RecordingAudio.inspect(url, job: job)
        let ranges = audio.ranges
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("localvoice-chunks-" + UUID().uuidString, isDirectory: true)
        if ranges.count > 1 {
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        }
        defer { if ranges.count > 1 { try? FileManager.default.removeItem(at: temporary) } }
        var results: [String] = []
        var homeUsed = false, macFallback = false, whisperUsed = false
        // After a remote failure, finish this recording on the Mac. The next
        // recording tries HP again instead of retrying a dead server per chunk.
        var tryRemote = preferHomeServer
        var homeServerFailure: String?
        for (index, range) in ranges.enumerated() {
            do {
                try job.check()
                let input: URL
                if ranges.count == 1 { input = url }
                else {
                    input = temporary.appendingPathComponent("chunk-\(index).wav")
                    try audio.write(range, from: url, to: input, job: job)
                }
                let suffix = ranges.count > 1 ? " · part \(index + 1) of \(ranges.count)" : ""
                progress("Recognizing speech" + suffix + "…", results.joined(separator: " "))
                var text: String?
                if tryRemote {
                    do { text = try recognize(input, true); homeUsed = true }
                    catch {
                        try job.check()
                        tryRemote = false; macFallback = true
                        homeServerFailure = error.localizedDescription
                        progress("HP unavailable · trying this Mac" + suffix + "…", results.joined(separator: " "))
                    }
                }
                if text == nil {
                    do { text = try recognize(input, false) }
                    catch {
                        try job.check()
                        progress("Mac engine unavailable · trying Whisper" + suffix + "…", results.joined(separator: " "))
                        text = try whisperFallback(input); whisperUsed = true
                    }
                }
                try job.check()
                let clean = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                // A successful empty response is not a transport failure and
                // should not trigger multiple models hallucinating over silence.
                if clean.isEmpty {
                    throw RecognitionFailure(message: ranges.count > 1
                        ? "Part \(index + 1) of \(ranges.count) returned no speech. Earlier recognized words are available for review."
                        : "No speech was detected. Try the saved recording with local Whisper.")
                } else {
                    guard !VocabularyEchoGuard.isSuspicious(clean, vocabulary: vocabulary) else {
                        throw RecognitionFailure(message: "The speech model may have repeated your vocabulary hints. Review the recognized words or retry.", partialText: (results + [clean]).joined(separator: " "))
                    }
                    guard clean.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) || $0 == "\n" || $0 == "\r" || $0 == "\t" }) else {
                        throw RecognitionFailure(message: "The speech engine returned invalid text.")
                    }
                    results.append(clean)
                }
                progress("Recognized speech" + suffix, results.joined(separator: " "))
                if ranges.count > 1 { try? FileManager.default.removeItem(at: input) }
            } catch {
                if job.isCancelled { throw CancellationError() }
                let previous = (error as? RecognitionFailure)?.partialText ?? ""
                throw RecognitionFailure(message: error.localizedDescription, partialText: previous.isEmpty ? results.joined(separator: " ") : previous)
            }
        }
        let text = results.joined(separator: " ")
        guard !text.isEmpty else { throw RecognitionFailure(message: "No speech was detected. The recording is saved for retry.") }
        return SpeechRecognitionResult(text: text, seconds: audio.seconds, usedHomeServer: homeUsed, usedMacFallback: macFallback, usedWhisperFallback: whisperUsed, homeServerFailure: homeServerFailure)
    }

    static func whisperCLI(audio: URL, data: URL, translate: Bool, vocabulary: [String], job: ProcessingJob) throws -> String {
        try job.check()
        let output = ProcessingJob.outputStem(for: audio)
        let textURL = output.appendingPathExtension("txt")
        defer { try? FileManager.default.removeItem(at: textURL) }
        let process = Process()
        process.executableURL = SpeechEngine.discoverBinary("whisper-cli", fallback: "/opt/homebrew/bin/whisper-cli")
        let model = AppResources.asset("ggml-large-v3.bin", userDirectory: data)
        guard FileManager.default.fileExists(atPath: model.path) else {
            throw RecognitionFailure(message: "The selected engine failed and the local Whisper fallback model is not installed.")
        }
        process.arguments = ["-m", model.path, "-f", audio.path, "-l", "auto", "-otxt", "-of", output.path, "-nt", "-t", "6"]
        if translate { process.arguments! += ["--translate"] }
        let prompt = TranscriptionPolicy.prompt(vocabulary)
        if !prompt.isEmpty { process.arguments! += ["--prompt", prompt] }
        let vad = AppResources.asset("ggml-silero-v6.2.0.bin", userDirectory: data)
        if FileManager.default.fileExists(atPath: vad.path) { process.arguments! += ["--vad", "-vm", vad.path] }
        // No persistent CLI logs containing audio, prompts, or recognized text.
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try job.run(process, timeout: TranscriptionPolicy.requestTimeout(seconds: RecordingAudio.duration(of: audio)) + 20)
        guard process.terminationStatus == 0,
              let text = try? String(contentsOf: textURL, encoding: .utf8) else {
            throw RecognitionFailure(message: "Both the selected speech engine and local Whisper fallback failed.")
        }
        return text
    }
}
