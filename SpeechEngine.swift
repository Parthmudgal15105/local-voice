import Foundation
import Darwin

// One app-owned, loopback-only helper. All inference and idle lifecycle work is serial.
final class SpeechEngine {
    private let queue = DispatchQueue(label: "localvoice.speech", qos: .userInitiated)
    private let lock = NSLock()
    private var process: Process?
    private var activeRequest: URLSessionDataTask?
    private var endpoint: URL?
    private var activeModel: URL?
    private var stopped = false
    private var generation = 0
    private var recordingActive = false // Accessed only on the serial queue.
    private let idleSeconds: Double
    init(idleSeconds: Double = 90) { self.idleSeconds = idleSeconds }
    var isWarm: Bool { lock.lock(); defer { lock.unlock() }; return process?.isRunning == true && endpoint != nil }
    var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    private struct Failure: LocalizedError {
        var message = "Speech engine unavailable."
        var errorDescription: String? { message }
    }
    private func request(_ request: URLRequest, job: ProcessingJob? = nil) throws -> Data {
        try job?.check()
        let session = URLSession(configuration: .ephemeral)
        let signal = DispatchSemaphore(value: 0)
        var data: Data?, response: URLResponse?, error: Error?
        let task = session.dataTask(with: request) { bytes, reply, problem in
            data = bytes; response = reply; error = problem; signal.signal()
        }
        lock.lock(); activeRequest = task; lock.unlock()
        defer {
            job?.finish(task)
            session.invalidateAndCancel()
            lock.lock(); if activeRequest === task { activeRequest = nil }; lock.unlock()
        }
        do {
            if let job { try job.resume(task) } else { task.resume() }
        } catch {
            task.cancel(); session.invalidateAndCancel(); throw error
        }
        let deadline = ProcessInfo.processInfo.systemUptime + request.timeoutInterval + 1
        while signal.wait(timeout: .now() + 0.05) != .success {
            try job?.check()
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw Failure(message: "Speech request timed out.") }
        }
        session.finishTasksAndInvalidate()
        try job?.check()
        if let error {
            let code = (error as NSError).code
            if code == NSURLErrorTimedOut { throw Failure(message: "Speech request timed out.") }
            if code == NSURLErrorCancelled { throw CancellationError() }
            if code == NSURLErrorAppTransportSecurityRequiresSecureConnection { throw Failure(message: "macOS blocked the HP HTTP route (ATS policy). Rebuild Local Voice with the private-server exception.") }
            throw Failure(message: "Speech connection failed (network code \(code)).")
        }
        guard let response = response as? HTTPURLResponse else { throw Failure(message: "Speech service returned no HTTP response.") }
        guard response.statusCode == 200 else { throw Failure(message: "Speech service returned HTTP \(response.statusCode).") }
        guard let data else { throw Failure(message: "Speech service returned no data.") }
        return data
    }
    private func availablePort() throws -> UInt16 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure() }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else { throw Failure() }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard result == 0 else { throw Failure() }
        return UInt16(bigEndian: address.sin_port)
    }
    static func discoverBinary(_ name: String, fallback: String) -> URL {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Engines/" + name), FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty,
                   FileManager.default.isExecutableFile(atPath: path) {
                    return URL(fileURLWithPath: path)
                }
            }
        } catch {}
        if FileManager.default.isExecutableFile(atPath: fallback) {
            return URL(fileURLWithPath: fallback)
        }
        let localFallback = "/usr/local/bin/" + name
        if FileManager.default.isExecutableFile(atPath: localFallback) {
            return URL(fileURLWithPath: localFallback)
        }
        return URL(fileURLWithPath: fallback)
    }
    private func ensure(model: URL, vad: URL, job: ProcessingJob? = nil) throws -> URL {
        try job?.check()
        lock.lock()
        if stopped { lock.unlock(); throw Failure() }
        if let process, process.isRunning, let endpoint, activeModel == model { lock.unlock(); return endpoint }
        lock.unlock()
        releaseHelper()
        let port = try availablePort()
        let path = "/" + UUID().uuidString
        let base = URL(string: "http://127.0.0.1:\(port)\(path)")!
        let helper = Process()
        let isQwen = model.hasDirectoryPath || model.lastPathComponent.hasPrefix("Qwen3-ASR")
        if isQwen {
            let bundled = Bundle.main.resourceURL?.appendingPathComponent("ASR/server.py")
            let source = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("asr/server.py")
            let script = bundled.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil } ?? source
            helper.executableURL = AppResources.python("asr")
            helper.environment = AppResources.environment()
            helper.arguments = ["-B", script.path, "--model", model.path, "--port", String(port), "--token", String(path.dropFirst())]
        } else {
            helper.executableURL = Self.discoverBinary("whisper-server", fallback: "/opt/homebrew/bin/whisper-server")
            helper.arguments = ["-m", model.path, "-t", "6", "-l", "auto", "-bs", "5", "-bo", "5", "--host", "127.0.0.1", "--port", String(port), "--request-path", path]
            if FileManager.default.fileExists(atPath: vad.path) { helper.arguments! += ["--vad", "-vm", vad.path] }
        }
        helper.standardOutput = FileHandle.nullDevice; helper.standardError = FileHandle.nullDevice
        lock.lock()
        guard !stopped else { lock.unlock(); throw Failure() }
        do { try job?.check(); try helper.run() } catch { lock.unlock(); throw error }
        process = helper; activeModel = model
        lock.unlock()
        let readyBy = ProcessInfo.processInfo.systemUptime + 30
        while ProcessInfo.processInfo.systemUptime < readyBy {
            do { try job?.check() } catch { releaseHelper(); throw error }
            guard !isStopped, helper.isRunning else { break }
            var health = URLRequest(url: base.appendingPathComponent("health")); health.timeoutInterval = 0.2
            if (try? request(health, job: job)) != nil {
                lock.lock()
                guard process === helper, !stopped, helper.isRunning else { lock.unlock(); throw Failure() }
                endpoint = base; lock.unlock()
                return base
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        releaseHelper(); throw Failure()
    }
    @discardableResult private func releaseHelper() -> Process? {
        lock.lock(); let old = process; process = nil; endpoint = nil; activeModel = nil; lock.unlock()
        if let old, old.isRunning {
            old.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { if old.isRunning { kill(old.processIdentifier, SIGKILL) } }
        }
        return old
    }
    private func scheduleIdleRelease() {
        generation += 1
        let token = generation
        queue.asyncAfter(deadline: .now() + idleSeconds) { [weak self] in
            guard let self, self.generation == token, !self.recordingActive else { return }
            self.releaseHelper()
        }
    }
    func setRecordingActive(_ active: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            self.recordingActive = active
            self.generation += 1
            if !active { self.scheduleIdleRelease() }
        }
    }
    func warm(model: URL, vad: URL, homeServerModel: String? = nil) {
        // Remote inference loads its model on demand. A long warm request
        // would block the next dictation's health check on this serial queue.
        guard homeServerModel == nil else { return }
        queue.async { [weak self] in
            guard let self else { return }
            _ = try? self.ensure(model: model, vad: vad)
            self.scheduleIdleRelease()
        }
    }
    private func homeServerRequest(path: String, body: [String: Any]? = nil, timeout: TimeInterval, job: ProcessingJob? = nil) throws -> Data {
        let dataDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Local Voice", isDirectory: true)
        guard let configuration = HomeSpeechServerConfiguration.load(in: dataDirectory) else { throw Failure(message: "HP configuration is missing or invalid.") }
        var request = URLRequest(url: configuration.url(path: path))
        request.httpMethod = body == nil ? "GET" : "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        try job?.check()
        return try self.request(request, job: job)
    }
    private func checkHomeServer(model: String, job: ProcessingJob?) throws {
        let bytes = try homeServerRequest(path: "/v1/health", timeout: 2, job: job)
        try job?.check()
        guard let health = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              health["ready"] as? Bool == true else { throw Failure(message: "HP is not ready.") }
        if model == "whisper" {
            guard health["whisper"] as? Bool == true else { throw Failure(message: "HP does not advertise the Whisper model.") }
        } else {
            guard (health["qwen"] as? [String])?.contains(model) == true else { throw Failure(message: "HP does not advertise the selected Qwen model.") }
        }
    }
    private func transcribeFromHomeServer(audio: URL, modelKey: String, translate: Bool, vocabulary: [String], job: ProcessingJob?) throws -> String {
        try job?.check()
        let audioBytes = try Data(contentsOf: audio)
        let prompt = TranscriptionPolicy.prompt(vocabulary)
        let bytes = try homeServerRequest(path: "/v1/inference", body: [
            "model": modelKey,
            "translate": translate,
            "prompt": prompt,
            "audioBase64": audioBytes.base64EncodedString()
        ], timeout: 175, job: job)
        guard let result = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let text = result["text"] as? String else { throw Failure() }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func romanizeOnHomeServer(words: [String], job: ProcessingJob? = nil) throws -> [String: String] {
        guard !words.isEmpty else { return [:] }
        let bytes = try homeServerRequest(path: "/v1/romanize", body: ["words": words], timeout: 50, job: job)
        guard let result = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let spellings = result["spellings"] as? [String: String], Set(spellings.keys) == Set(words) else {
            throw Failure()
        }
        return spellings
    }
    func transcribe(audio: URL, model: URL, vad: URL, translate: Bool, vocabulary: [String], homeServerModel: String? = nil, job: ProcessingJob? = nil) throws -> String {
        try queue.sync {
            try job?.check()
            if let homeServerModel {
                try checkHomeServer(model: homeServerModel, job: job)
                // A previous Mac fallback may still be warm. Once HP is ready,
                // release it before the remote request occupies this queue.
                generation += 1
                if let old = releaseHelper() {
                    for _ in 0..<14 where old.isRunning { Thread.sleep(forTimeInterval: 0.05) }
                    guard !old.isRunning else { throw Failure() }
                }
                return try transcribeFromHomeServer(audio: audio, modelKey: homeServerModel, translate: translate, vocabulary: vocabulary, job: job)
            }
            let base = try ensure(model: model, vad: vad, job: job)
            defer { scheduleIdleRelease() }
            if model.lastPathComponent.hasPrefix("Qwen3-ASR") {
                guard !translate else { throw Failure() }
                var query = URLRequest(url: base.appendingPathComponent("inference"))
                query.httpMethod = "POST"; query.timeoutInterval = TranscriptionPolicy.requestTimeout(seconds: RecordingAudio.duration(of: audio))
                query.setValue("application/json", forHTTPHeaderField: "Content-Type")
                query.httpBody = try JSONSerialization.data(withJSONObject: ["audio": audio.path, "vocabulary": TranscriptionPolicy.vocabulary(vocabulary)])
                do {
                    let bytes = try request(query, job: job)
                    guard let result = try JSONSerialization.jsonObject(with: bytes) as? [String:Any], let text = result["text"] as? String else { throw Failure() }
                    return text.trimmingCharacters(in: .whitespacesAndNewlines)
                } catch { releaseHelper(); throw error }
            }
            let boundary = UUID().uuidString
            var body = Data()
            func append(_ text: String) { body.append(Data(text.utf8)) }
            let fields = ["language":"auto", "translate":translate ? "true":"false", "response_format":"json", "beam_size":"5", "best_of":"5", "token_timestamps":"false", "no_timestamps":"true", "prompt":TranscriptionPolicy.prompt(vocabulary)]
            for (name, value) in fields {
                append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
            }
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"dictation.wav\"\r\nContent-Type: audio/wav\r\n\r\n")
            body.append(try Data(contentsOf: audio)); append("\r\n--\(boundary)--\r\n")
            var query = URLRequest(url: base.appendingPathComponent("inference"))
            query.httpMethod = "POST"; query.timeoutInterval = TranscriptionPolicy.requestTimeout(seconds: RecordingAudio.duration(of: audio))
            query.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            query.httpBody = body
            do {
                let bytes = try request(query, job: job)
                guard let result = try JSONSerialization.jsonObject(with: bytes) as? [String: Any], let text = result["text"] as? String else { throw Failure() }
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch { releaseHelper(); throw error }
        }
    }
    func cancelCurrent() {
        lock.lock(); let task = activeRequest; lock.unlock()
        task?.cancel(); releaseHelper()
    }
    func shutdown() {
        lock.lock(); stopped = true; lock.unlock()
        releaseHelper()
    }
    deinit { shutdown() }
}
