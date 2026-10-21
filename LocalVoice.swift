import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import Combine
import CoreText

struct WisprSnapshot: Codable {
    let source: String
    let words: Int
    let wpm: Int
    let fixes: Int
    let wordsCorrected: Int
    let dictionaryFixes: Int
    let desktopWords: Int
    let appsUsed: Int
    let streak: Int
    let longestStreak: Int
    let aiPrompts: Int
    let otherTasks: Int
    let emails: Int
    let workMessages: Int
    let personalMessages: Int
    let documents: Int
    let aiPercent: Int
    let otherPercent: Int
}
final class VoiceModel: ObservableObject {
    static let shared = VoiceModel()
    @Published var status = "Hold Fn to dictate"
    @Published var recording = false
    @Published var busy = false
    @Published var showProcessingError = false
    @Published var transcript = ""
    @Published var enabled = true { didSet { if !enabled { releaseFn(cancel: true) } } }
    @Published var tab = CommandLine.arguments.contains("--insights") ? "Insights" : "Dictation"
    @Published var sessions: [Session] = []
    @Published var imported: WisprSnapshot?
    @Published var preferences = Preferences() { didSet { savePreferences() } }
    @Published var history: [TranscriptEntry] = []
    @Published var learningSamples: [LearningSample] = []
    @Published var learningStatus = "Verify recordings to build your personal training set."
    @Published var trainingVoice = false
    var learningJob: ProcessingJob?
    var trainingSchedule = TrainingSchedule()
    var shuttingDown = false
    var lastCorrectionEdit = Date.distantPast
    var correctionSaves: [UUID: DispatchWorkItem] = [:]
    func speechForLearningShutdown() { speechEngine.cancelCurrent() }
    @Published var accessibilityReady = false
    @Published var inputReady = false
    @Published var lastShortcutEvent = "No Fn event received yet"
    @Published var inputLevel: Double = 0
    @Published var search = ""
    @Published var newTerm = ""
    @Published var ruleSpoken = ""
    @Published var ruleWritten = ""
    @Published var snippetSpoken = ""
    @Published var snippetWritten = ""
    @Published var shortcutReady = false
    @Published var microphoneReady = false
    private var recorder: AVAudioRecorder?
    private var target: NSRunningApplication?
    private var intoScratchpad = false
    private var started = Date()
    private var recordingURL: URL?
    private var recordingPreferences: Preferences?
    private var recordingConfiguration: DictationConfiguration?
    @Published var recordingSeconds: Double = 0
    @Published var liveTranscript = ""
    @Published var liveProgress = ""
    private var liveSession: LiveTranscriptionSession?
    private var timeout: Timer?
    private var meter: Timer?
    private var peakPower: Float = -160
    @Published var readinessTick = 0
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var fnDown = false
    private var gesture = FnGesture()
    var continuousListening: Bool { gesture.mode == .continuous }
    private var pending: DispatchWorkItem?
    private var worker: Process?
    private var processingJob: ProcessingJob?
    private var processingTimeout: Timer?
    @Published var recoveryText = ""
    @Published var recoveryRecordings: [URL] = []
    private let speechEngine = SpeechEngine()
    let data = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Local Voice")
    private var recordingsDirectory: URL { data.appendingPathComponent("Recoverable Recordings", isDirectory: true) }
    private func metadataURL(for audio: URL) -> URL { audio.appendingPathExtension("json") }
    private func recoveryConfiguration(for audio: URL) -> DictationConfiguration? {
        guard let bytes = try? Data(contentsOf: metadataURL(for: audio)),
              let metadata = try? JSONDecoder().decode(RecordingRecoveryMetadata.self, from: bytes), metadata.version == 1 else { return nil }
        return metadata.configuration
    }
    private func removeRecording(_ audio: URL) {
        try? FileManager.default.removeItem(at: audio)
        try? FileManager.default.removeItem(at: metadataURL(for: audio))
    }
    private func modelURL(for configuration: DictationConfiguration) -> URL {
        if !configuration.translateToEnglish, configuration.speechModel != "whisper" {
            let qwen = AppResources.asset("asr-models/" + (configuration.speechModel == "qwen-1.7" ? "Qwen3-ASR-1.7B-8bit" : "Qwen3-ASR-0.6B-8bit"))
            if FileManager.default.fileExists(atPath: qwen.appendingPathComponent("model.safetensors").path),
               FileManager.default.isExecutableFile(atPath: AppResources.python("asr").path) { return qwen }
        }
        return AppResources.asset("ggml-large-v3.bin")
    }
    private func refreshRecoveryRecordings() {
        let files = (try? FileManager.default.contentsOfDirectory(at: recordingsDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        recoveryRecordings = files.filter { $0.pathExtension.lowercased() == "wav" }
            .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
    }
    func retryRecording(_ url: URL, usingCurrentSettings: Bool = false, usingWhisper: Bool = false) {
        guard !recording, !busy, recoveryRecordings.contains(url), FileManager.default.fileExists(atPath: url.path) else { return }
        showProcessingError = false
        target = nil; intoScratchpad = false
        var configuration = (usingCurrentSettings ? nil : recoveryConfiguration(for: url))
            ?? DictationConfiguration(preferences: preferences, preferHomeServer: usesHomeServerForSpeech)
        if usingWhisper { configuration.speechModel = "whisper"; configuration.preferHomeServer = false }
        transcribe(url, seconds: 0, destination: nil, configuration: configuration)
    }
    func revealRecording(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    func recordingLabel(_ url: URL) -> String {
        guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return url.lastPathComponent }
        let mode = recoveryConfiguration(for: url).map { $0.translateToEnglish ? "English" : "Hinglish" }
        return "Recording · " + date.formatted(date: .abbreviated, time: .shortened) + (mode.map { " · " + $0 } ?? "")
    }
    var qwenURL: URL { AppResources.asset("asr-models/" + (preferences.speechModel == "qwen-1.7" ? "Qwen3-ASR-1.7B-8bit" : "Qwen3-ASR-0.6B-8bit")) }
    var qwenReady: Bool { FileManager.default.fileExists(atPath: qwenURL.appendingPathComponent("model.safetensors").path) && FileManager.default.isExecutableFile(atPath: AppResources.python("asr").path) }
    var qwenSelected: Bool { !preferences.translates && preferences.speechModel != "whisper" }
    var homeServerConfigured: Bool { HomeSpeechServerConfiguration.isConfigured(in: data) }
    var usesHomeServerForSpeech: Bool {
        preferences.homeServerForSpeech ?? HomeSpeechServerConfiguration.isConfigured(in: data)
    }
    var homeServerModel: String {
        if preferences.translates || preferences.speechModel == "whisper" { return "whisper" }
        return preferences.speechModel == "qwen-1.7" ? "qwen-1.7" : "qwen-0.6"
    }
    var usesQwen: Bool { qwenSelected && qwenReady }
    var modelURL: URL { usesQwen ? qwenURL : AppResources.asset("ggml-large-v3.bin") }
    var modelName: String {
        let name = (usesHomeServerForSpeech ? qwenSelected : usesQwen) ? (preferences.speechModel == "qwen-1.7" ? "Qwen3-ASR 1.7B" : "Qwen3-ASR 0.6B") : "Whisper Large-v3"
        return usesHomeServerForSpeech && !qwenSelected ? "Whisper Large-v3 Turbo (HP)" : name
    }
    var modelReady: Bool {
        if usesHomeServerForSpeech && HomeSpeechServerConfiguration.isConfigured(in: data) { return true }
        if qwenSelected && qwenReady { return true }
        return FileManager.default.fileExists(atPath: AppResources.asset("ggml-large-v3.bin").path)
    }
    var totalWords: Int { sessions.reduce(0) { $0 + $1.words } }
    var totalSeconds: Double { sessions.reduce(0) { $0 + $1.seconds } }
    var wpm: Int { totalSeconds > 0 ? Int(Double(totalWords) / totalSeconds * 60) : 0 }
    var appUsage: [(String, Int)] {
        Dictionary(grouping: sessions, by: \.app).map { ($0.key, $0.value.reduce(0) { $0 + $1.words }) }.sorted { $0.1 > $1.1 }
    }
    var activeDays: Set<Date> { Set(sessions.map { Calendar.current.startOfDay(for: $0.date) }) }
    var streak: Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: Date())
        if !activeDays.contains(day) { day = cal.date(byAdding: .day, value: -1, to: day)! }
        var count = 0
        while activeDays.contains(day) { count += 1; day = cal.date(byAdding: .day, value: -1, to: day)! }
        return count
    }
    init() {
        try? FileManager.default.createDirectory(at: data, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: data.path)
        try? FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: recordingsDirectory.path)
        refreshRecoveryRecordings()
        if let bytes = try? Data(contentsOf: data.appendingPathComponent("usage.json")), let saved = try? JSONDecoder().decode([Session].self, from: bytes) { sessions = saved }
        if let bytes = try? Data(contentsOf: data.appendingPathComponent("preferences.json")), let saved = try? JSONDecoder().decode(Preferences.self, from: bytes) { preferences = saved }
        if preferences.saveHistory, let bytes = try? Data(contentsOf: data.appendingPathComponent("history.json")), let saved = try? JSONDecoder().decode([TranscriptEntry].self, from: bytes) { history = saved }
        if let bytes = try? Data(contentsOf: data.appendingPathComponent("wispr-import.json")) { imported = try? JSONDecoder().decode(WisprSnapshot.self, from: bytes) }
        loadLearning()
        microphoneReady = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.readinessTick += 1
            self.maybeTrainVoice()
            self.microphoneReady = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            self.accessibilityReady = AXIsProcessTrusted()
            self.inputReady = CGPreflightListenEventAccess()
            if let tap = self.tap { self.shortcutReady = CGEvent.tapIsEnabled(tap: tap) }
            if self.tap == nil { self.installShortcut() }
        }
        installShortcut()
    }
    func permissions() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in DispatchQueue.main.async { self.microphoneReady = granted } }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        installShortcut()
    }
    func installShortcut() {
        accessibilityReady = AXIsProcessTrusted()
        inputReady = CGPreflightListenEventAccess()
        guard tap == nil, accessibilityReady || inputReady else { return }
        let mask = (CGEventMask(1) << CGEventType.flagsChanged.rawValue) | (CGEventMask(1) << CGEventType.keyDown.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: accessibilityReady ? .defaultTap : .listenOnly, eventsOfInterest: mask, callback: { _, type, event, _ in
            let model = VoiceModel.shared
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = model.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                model.releaseFn(cancel: true)
                return Unmanaged.passUnretained(event)
            }
            guard model.enabled else { return Unmanaged.passUnretained(event) }
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            if type == .keyDown {
                if model.fnDown && !model.recording { model.pending?.cancel(); model.gesture.cancelPending() }
                if code == 53 && (model.recording || model.busy || model.showProcessingError) { model.cancelCurrent(); return nil }
                return Unmanaged.passUnretained(event)
            }
            let down = event.flags.contains(.maskSecondaryFn)
            guard down != model.fnDown else { return Unmanaged.passUnretained(event) }
            model.fnDown = down
            model.lastShortcutEvent = "Fn \(down ? "pressed" : "released") at " + Date().formatted(date: .omitted, time: .standard)
            if down {
                model.perform(model.gesture.press(doubleTapInterval: NSEvent.doubleClickInterval))
                let work = DispatchWorkItem { model.perform(model.gesture.hold()) }
                model.pending = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
            } else {
                model.pending?.cancel(); model.pending = nil
                model.perform(model.gesture.release())
            }
            return model.accessibilityReady && code == 63 ? nil : Unmanaged.passUnretained(event)
        }, userInfo: nil)
        if let tap {
            tapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), tapSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            shortcutReady = true
        } else { status = "Keyboard listener unavailable. Check macOS access in Settings." }
    }
    func reconnectShortcut() {
        releaseFn(cancel: true)
        if let source = tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil; tapSource = nil; shortcutReady = false
        installShortcut()
        status = shortcutReady ? "Fn connected · tap or hold to dictate" : "macOS has not granted keyboard access to this build yet."
    }
    func perform(_ action: FnGesture.Action) {
        switch action {
        case .begin: start(); if !recording { gesture.reset() }
        case .listenContinuously:
            if recording {
                timeout?.invalidate(); timeout = nil
                status = "Continuous listening · press Fn to finish"
            } else { gesture.reset() }
        case .end: if recording { stop() }
        case .none: break
        }
    }
    func toggleRecording() { if recording { releaseFn(cancel: false) } else { start() } }
    func savePreferences() {
        do {
            let url = data.appendingPathComponent("preferences.json")
            try JSONEncoder().encode(preferences).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            if !preferences.saveHistory { try? FileManager.default.removeItem(at: data.appendingPathComponent("history.json")) }
            else { persistHistory() }
        } catch { status = "Could not save preferences: " + error.localizedDescription }
    }
    func persistHistory() {
        guard preferences.saveHistory else { return }
        let url = data.appendingPathComponent("history.json")
        do { try JSONEncoder().encode(Array(history.prefix(50))).write(to: url, options: .atomic); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }
        catch { status = "Could not save transcript history." }
    }
    func releaseFn(cancel: Bool) {
        fnDown = false; pending?.cancel(); pending = nil; gesture.reset()
        if recording { stop(cancel: cancel) }
    }
    func start() {
        guard enabled, !recording, !busy, !trainingVoice else { return }
        guard modelReady else { status = "Model download is not complete yet."; return }
        guard microphoneReady else { status = "Enable Microphone access to record."; return }
        showProcessingError = false
        let capturedPreferences = preferences
        let configuration = DictationConfiguration(preferences: capturedPreferences, preferHomeServer: usesHomeServerForSpeech)
        target = NSWorkspace.shared.frontmostApplication
        intoScratchpad = target?.processIdentifier == ProcessInfo.processInfo.processIdentifier && tab == "Scratchpad"
        let url = recordingsDirectory.appendingPathComponent("local-voice-\(UUID().uuidString).wav")
        do {
            guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw NSError(domain: "LocalVoice", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create a private recording file."])
            }
            let metadata = metadataURL(for: url)
            try JSONEncoder().encode(RecordingRecoveryMetadata(configuration: configuration)).write(to: metadata, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: metadata.path)
            recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000.0, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false])
            recorder?.isMeteringEnabled = true
            guard recorder?.record() == true else { throw NSError(domain: "LocalVoice", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not start the microphone."]) }
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            peakPower = -160
            meter = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                guard let self, let recorder = self.recorder else { return }
                recorder.updateMeters(); self.peakPower = max(self.peakPower, recorder.averagePower(forChannel: 0)); self.inputLevel = min(1, max(0, Double(recorder.averagePower(forChannel: 0) + 60) / 60))
                self.recordingSeconds = Date().timeIntervalSince(self.started)
            }
            recordingPreferences = capturedPreferences; recordingConfiguration = configuration; recordingSeconds = 0
            liveTranscript = ""; liveProgress = ""
            speechEngine.setRecordingActive(true)
            speechEngine.warm(model: modelURL(for: configuration), vad: AppResources.asset("ggml-silero-v6.2.0.bin"), homeServerModel: configuration.homeServerModel)
            recordingURL = url; started = Date(); recording = true; status = "Listening · tap Fn or release your hold to finish"
            if capturedPreferences.transcribeWhileRecording ?? true {
                let id = UUID(), engine = speechEngine, data = self.data, model = modelURL(for: configuration)
                let vad = AppResources.asset("ggml-silero-v6.2.0.bin")
                do {
                    let session = try LiveTranscriptionSession(id: id, audio: url, preferHomeServer: configuration.preferHomeServer, recognize: { audio, remote, job in
                        try SpeechTranscription.recognize(audio: audio, data: data, model: model, vad: vad, translate: capturedPreferences.translates, vocabulary: capturedPreferences.vocabulary, homeServerModel: remote ? configuration.homeServerModel : nil, engine: engine, job: job, progress: { _, _ in })
                    }, progress: { [weak self] phase, partial, _ in
                        DispatchQueue.main.async {
                            guard let self, self.liveSession?.id == id else { return }
                            self.liveProgress = phase
                            if !partial.isEmpty { self.liveTranscript = partial; self.recoveryText = partial }
                            if !self.recording { self.status = phase }
                        }
                    })
                    liveSession = session; session.start()
                    liveProgress = "Long dictations process in the background"
                } catch { liveProgress = "Audio is safe · processing will start when you finish" }
            }
            timeout = Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { [weak self] _ in self?.releaseFn(cancel: false) }
        } catch { status = error.localizedDescription; recorder = nil; recordingPreferences = nil; recordingConfiguration = nil; removeRecording(url) }
    }
    func stop(cancel: Bool = false) {
        guard recording, let url = recordingURL else { return }
        meter?.invalidate(); meter = nil
        recorder?.stop(); recorder = nil; recordingURL = nil; recording = false; timeout?.invalidate(); timeout = nil
        speechEngine.setRecordingActive(false)
        let seconds = Date().timeIntervalSince(started)
        let capturedPreferences = recordingPreferences, configuration = recordingConfiguration
        recordingPreferences = nil; recordingConfiguration = nil
        guard !cancel else {
            if let liveSession { liveSession.cancel(); self.liveSession = nil; speechEngine.cancelCurrent() }
            liveTranscript = ""; liveProgress = ""; recoveryText = ""
            removeRecording(url); status = "Cancelled"; return
        }
        if let liveSession {
            busy = true; status = "Finishing the remaining speech…"
            let destination = target
            processingTimeout?.invalidate()
            let limit = TranscriptionPolicy.overallTimeout(seconds: RecordingAudio.duration(of: url), remote: configuration?.preferHomeServer ?? false)
            processingTimeout = Timer.scheduledTimer(withTimeInterval: limit, repeats: false) { [weak self] _ in
                guard let self, self.liveSession === liveSession else { return }
                liveSession.cancel(); self.liveSession = nil; self.speechEngine.cancelCurrent()
                self.transcribe(url, seconds: seconds, destination: destination, configuration: configuration, capturedPreferences: capturedPreferences, partialText: self.recoveryText)
            }
            liveSession.finish { [weak self] recognized, partial in
                DispatchQueue.main.async {
                    guard let self, self.liveSession === liveSession else { return }
                    self.liveSession = nil
                    self.transcribe(url, seconds: seconds, destination: destination, configuration: configuration, capturedPreferences: capturedPreferences, recognized: recognized, partialText: partial)
                }
            }
            return
        }
        // Inspect actual PCM frames off the main thread. A fast spoken word can
        // be valid even before the first meter update or 400 ms has elapsed.
        transcribe(url, seconds: seconds, destination: target, configuration: configuration, capturedPreferences: capturedPreferences)
    }
    func cancelCurrent() {
        showProcessingError = false
        if recording { releaseFn(cancel: true); return }
        guard busy else { return }
        liveSession?.cancel(); liveSession = nil
        processingJob?.cancel(); processingJob = nil
        processingTimeout?.invalidate(); processingTimeout = nil
        speechEngine.cancelCurrent(); busy = false
        refreshRecoveryRecordings()
        status = "Cancelled · recording saved for retry in Local Voice"
    }
    func transcribe(_ url: URL, seconds: Double, destination: NSRunningApplication?, configuration: DictationConfiguration? = nil, capturedPreferences: Preferences? = nil, recognized: SpeechRecognitionResult? = nil, partialText: String = "") {
        let configuration = configuration ?? DictationConfiguration(preferences: preferences, preferHomeServer: usesHomeServerForSpeech)
        let preferences = configuration.applying(to: capturedPreferences ?? self.preferences)
        let homeServerModel = configuration.homeServerModel
        let duration = RecordingAudio.duration(of: url)
        let deadline = TranscriptionPolicy.overallTimeout(seconds: duration, remote: homeServerModel != nil)
        let job = ProcessingJob(timeout: deadline)
        processingJob = job; recoveryText = partialText
        processingTimeout?.invalidate()
        processingTimeout = Timer.scheduledTimer(withTimeInterval: deadline, repeats: false) { [weak self] _ in
            guard let self, self.processingJob === job else { return }
            self.cancelCurrent(); self.showProcessingError = true; self.status = "Processing timed out. Recording saved for retry."
        }
        busy = true; status = recognized == nil ? "Checking recording…" : "Finishing your transcript…"
        let vad = AppResources.asset("ggml-silero-v6.2.0.bin")
        let writeToScratchpad = self.intoScratchpad
        let spellingCache = data.appendingPathComponent("hinglish-xlit-spellings.json")
        let engine = speechEngine, model = modelURL(for: configuration), data = self.data
        DispatchQueue.global(qos: .userInitiated).async {
            var text = "", failure = ""
            var usedHomeServer = false, usedMacFallback = false, usedWhisperFallback = false
            var usedMacSpelling = false
            var homeServerFailure: String?
            var recordingDuration = duration
            do {
                let recognized = try recognized ?? SpeechTranscription.recognize(audio: url, data: data, model: model, vad: vad, translate: preferences.translates, vocabulary: preferences.vocabulary, homeServerModel: homeServerModel, engine: engine, job: job) { phase, partial in
                    DispatchQueue.main.async {
                        guard self.processingJob === job, !job.isCancelled else { return }
                        self.status = phase
                        if !partial.isEmpty { self.recoveryText = partial }
                    }
                }
                text = recognized.text; recordingDuration = recognized.seconds
                usedHomeServer = recognized.usedHomeServer; usedMacFallback = recognized.usedMacFallback
                usedWhisperFallback = recognized.usedWhisperFallback
                homeServerFailure = recognized.homeServerFailure
            } catch {
                failure = error.localizedDescription
                if let partial = (error as? RecognitionFailure)?.partialText, !partial.isEmpty { text = partial }
            }
            let rawText = text
            if failure.isEmpty && !preferences.translates && !text.isEmpty && !job.isCancelled {
                DispatchQueue.main.async { guard self.processingJob === job else { return }; self.recoveryText = rawText; self.status = "Spelling Hinglish…" }
                do {
                    if usedHomeServer {
                        do {
                            text = try Hinglish.convertOnHomeServer(text, cacheURL: spellingCache, job: job) { words in
                                try engine.romanizeOnHomeServer(words: words, job: job)
                            }
                        } catch {
                            try job.check()
                            usedMacSpelling = true
                            text = try Hinglish.convert(text, cacheURL: spellingCache, job: job)
                        }
                    } else {
                        text = try Hinglish.convert(text, cacheURL: spellingCache, job: job)
                    }
                }
                catch { failure = error.localizedDescription }
            }
            let processed = TextProcessing.apply(text, corrections: preferences.corrections, snippets: preferences.snippets)
            let result = processed.text, error = failure, macFallback = usedMacFallback, whisperFallback = usedWhisperFallback, audioDuration = recordingDuration
            let hpSpeech = usedHomeServer, macSpelling = usedMacSpelling, hpFailure = homeServerFailure
            DispatchQueue.main.async {
                guard self.processingJob === job else { return }
                guard !job.isCancelled else { self.cancelCurrent(); return }
                self.processingTimeout?.invalidate(); self.processingTimeout = nil; self.processingJob = nil
                self.worker = nil; self.busy = false
                if error.isEmpty { self.recoveryText = "" } else if !rawText.isEmpty { self.recoveryText = rawText }
                guard error.isEmpty else { self.refreshRecoveryRecordings(); self.status = error + " Recording saved for retry."; self.showProcessingError = true; return }
                guard !result.isEmpty else { self.refreshRecoveryRecordings(); self.status = "No speech detected · recording saved for retry"; self.showProcessingError = true; return }
                // Translation should never insert an untranslated Hindi transcript.
                guard result.range(of: "[\\u0900-\\u097F]", options: .regularExpression) == nil else { self.transcript = result; self.refreshRecoveryRecordings(); self.status = "Translation contained Hindi text. Recording saved for retry."; self.showProcessingError = true; return }
                let learningID = seconds > 0 ? self.captureLearning(url, text: result, seconds: audioDuration, capturedPreferences: preferences) : nil
                self.removeRecording(url)
                self.refreshRecoveryRecordings()
                self.transcript = result
                self.history.insert(TranscriptEntry(app: destination?.localizedName ?? "Local Voice", text: result, sourceText: rawText, learningSampleID: learningID), at: 0)
                self.history = Array(self.history.prefix(50)); self.persistHistory()
                if seconds > 0 {
                    self.sessions.append(Session(date: Date(), seconds: audioDuration, words: result.split(whereSeparator: { $0.isWhitespace }).count, app: destination?.localizedName ?? "Unknown"))
                    do {
                        let history = self.data.appendingPathComponent("usage.json")
                        try JSONEncoder().encode(self.sessions).write(to: history, options: .atomic)
                        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: history.path)
                    } catch { self.status = "Transcript ready; usage could not be saved." }
                }
                if writeToScratchpad {
                    self.preferences.scratchpad += (self.preferences.scratchpad.isEmpty ? "" : "\n\n") + result
                    self.status = "Added to scratchpad"
                } else { self.insert(result, into: destination) }
                if hpSpeech { self.status += " · HP speech" }
                else if !macFallback { self.status += " · Mac speech" }
                if macFallback { self.status += " · Mac speech fallback" }
                if whisperFallback { self.status += " · Whisper fallback" }
                if macSpelling { self.status += " · Mac spelling fallback" }
                if let hpFailure { self.status += " · HP: " + hpFailure }
            }
        }
    }
    func copy() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(transcript, forType: .string) }
    func insert(_ text: String, into app: NSRunningApplication?) {
        // Always retain the latest dictation so an inaccessible editor can use manual paste.
        let clipboard = NSPasteboard.general
        clipboard.clearContents(); clipboard.setString(text, forType: .string)
        status = "Copied to clipboard · paste wherever you like"
        guard let app, !app.isTerminated,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
              AXIsProcessTrusted() else { return }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &value)
        let customEditorFallback = TextDelivery.supportsUnexposedEditor(bundleID: app.bundleIdentifier ?? "")
        guard focusResult == .success, let value else {
            if customEditorFallback { sendPaste() }
            return
        }
        let focused = value as! AXUIElement
        func attribute(_ name: String) -> CFTypeRef? {
            var result: CFTypeRef?
            guard AXUIElementCopyAttributeValue(focused, name as CFString, &result) == .success else { return nil }
            return result
        }
        if (attribute(kAXSubroleAttribute) as? String) == "AXSecureTextField" {
            status = "Copied to clipboard · password field skipped"; return
        }
        let role = attribute(kAXRoleAttribute) as? String ?? ""
        var selectedTextSettable: DarwinBoolean = false
        _ = AXUIElementIsAttributeSettable(focused, kAXSelectedTextAttribute as CFString, &selectedTextSettable)
        let editable = (attribute("AXEditable") as? Bool) == true
        guard customEditorFallback || TextDelivery.canPaste(role: role, editable: editable, selectionSettable: selectedTextSettable.boolValue) else { return }
        sendPaste()
    }
    private func sendPaste() {
        // Web editors and custom controls commonly reject AX text assignment; Command-V
        // follows the editor's normal paste handling and preserves selected-text replacement.
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        status = "Paste sent · also copied to clipboard"
    }
    func shutdown() { shuttingDown=true; flushHistoryCorrections(); learningJob?.cancel(); liveSession?.cancel(); liveSession = nil; processingJob?.cancel(); processingTimeout?.invalidate(); pending?.cancel(); if recording { stop(cancel: true) }; speechEngine.shutdown(); if let worker, worker.isRunning { worker.terminate() } }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel?
    private var observation: AnyCancellable?
    func applicationWillFinishLaunching(_ notification: Notification) {
        if let fonts = Bundle.main.resourceURL?.appendingPathComponent("Fonts"), let files = try? FileManager.default.contentsOfDirectory(at: fonts, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "ttf" { CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil) }
        }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let icon = Bundle.main.url(forResource: "LocalVoice", withExtension: "icns") { NSApp.applicationIconImage = NSImage(contentsOf: icon) }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 64), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.ignoresMouseEvents = false
        panel.contentView = NSHostingView(rootView: RecordingPill())
        self.panel = panel
        observation = VoiceModel.shared.$recording.combineLatest(VoiceModel.shared.$busy, VoiceModel.shared.$showProcessingError).receive(on: DispatchQueue.main).sink { recording, busy, failed in
            if recording || busy || failed {
                if let screen = NSScreen.main { panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - 210, y: screen.visibleFrame.minY + 30)) }
                panel.orderFrontRegardless()
            } else { panel.orderOut(nil) }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { VoiceModel.shared.shutdown() }
}
struct RecordingPill: View {
    @ObservedObject var model = VoiceModel.shared
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: model.recording ? "mic.fill" : "hourglass").foregroundStyle(model.recording ? .red : .teal)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.recording ? (model.continuousListening ? "Continuous listening" : "Listening") + String(format: " · %d:%02d", Int(model.recordingSeconds) / 60, Int(model.recordingSeconds) % 60) : model.status).font(.system(size: 13, weight: .medium)).lineLimit(2)
                if model.recording && !model.liveProgress.isEmpty { Text(model.liveProgress).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer()
            if model.recording {
                Button { model.releaseFn(cancel: false) } label: { Image(systemName: "stop.circle.fill").font(.system(size: 23)) }.buttonStyle(.plain).help("Finish dictation").accessibilityLabel("Finish dictation")
            }
            if model.showProcessingError {
                Button { model.tab = "Dictation"; NSApp.activate(ignoringOtherApps: true); NSApp.windows.first(where: { $0.title == "Local Voice" })?.makeKeyAndOrderFront(nil) } label: { Image(systemName: "arrow.up.right.square") }.buttonStyle(.plain).help("View recovered transcript")
            }
            Button { model.cancelCurrent() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 20)) }.buttonStyle(.plain).help("Cancel · Escape")
        }.padding(16).frame(width: 420, height: 64).background(.regularMaterial, in: Capsule())
    }
}
@main struct LocalVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject var model = VoiceModel.shared
    var body: some Scene {
        Window("Local Voice", id: "main") { Dashboard() }.windowStyle(.hiddenTitleBar).defaultSize(width: 1180, height: 760)
        MenuBarExtra {
            Text(model.status)
            Toggle("Fn enabled", isOn: $model.enabled)
            Button("Open Local Voice") { NSApp.activate(ignoringOtherApps: true); NSApp.windows.first(where: { $0.title == "Local Voice" })?.makeKeyAndOrderFront(nil) }
            Button("Quit") { NSApp.terminate(nil) }
        } label: { Image(systemName: model.recording ? "mic.fill" : model.busy ? "hourglass" : "waveform") }
    }
}
