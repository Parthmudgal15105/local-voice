import Foundation
import Darwin

final class ProcessingJob {
    static func outputStem(for recording: URL) -> URL {
        recording.deletingLastPathComponent().appendingPathComponent("local-voice-processing-\(UUID().uuidString)")
    }

    private let lock = NSLock()
    private var cancelled = false
    private var child: Process?
    private var request: URLSessionDataTask?
    private let deadline: TimeInterval
    init(timeout: TimeInterval = 60) { deadline = ProcessInfo.processInfo.systemUptime + timeout }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled || ProcessInfo.processInfo.systemUptime >= deadline }
    func check() throws { if isCancelled { throw CancellationError() } }
    // Serialize starting a network request with cancellation. Once cancel()
    // wins this lock, no new request belonging to this job can be resumed.
    func resume(_ task: URLSessionDataTask) throws {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled, ProcessInfo.processInfo.systemUptime < deadline else { throw CancellationError() }
        request = task
        task.resume()
    }
    func finish(_ task: URLSessionDataTask) {
        lock.lock(); defer { lock.unlock() }
        if request === task { request = nil }
    }
    func cancel() {
        lock.lock(); cancelled = true; let process = child; let task = request; request = nil; lock.unlock()
        task?.cancel()
        if let process, process.isRunning {
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
        }
    }
    func run(_ process: Process, timeout: TimeInterval = 30) throws {
        lock.lock()
        guard !cancelled, ProcessInfo.processInfo.systemUptime < deadline else { lock.unlock(); throw CancellationError() }
        do { try process.run(); child = process; lock.unlock() } catch { lock.unlock(); throw error }
        defer { lock.lock(); child = nil; lock.unlock() }
        let end = min(deadline, ProcessInfo.processInfo.systemUptime + timeout)
        while process.isRunning {
            if isCancelled || ProcessInfo.processInfo.systemUptime >= end { cancel(); throw CancellationError() }
            Thread.sleep(forTimeInterval: 0.03)
        }
        try check()
    }
}
