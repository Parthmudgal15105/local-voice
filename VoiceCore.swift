import Foundation

struct FnGesture {
    enum Mode { case idle, pending, held, toggled, continuous, ignoreRelease }
    enum Action: Equatable { case none, begin, end, listenContinuously }
    private(set) var mode: Mode = .idle
    private var lastTap: TimeInterval?
    mutating func press(at time: TimeInterval = ProcessInfo.processInfo.systemUptime, doubleTapInterval: TimeInterval = 0.5) -> Action {
        switch mode {
        case .idle: mode = .pending; return .none
        case .toggled:
            if let lastTap, time - lastTap >= 0, time - lastTap <= doubleTapInterval {
                mode = .continuous; self.lastTap = nil; return .listenContinuously
            }
            mode = .ignoreRelease; return .end
        case .continuous: mode = .ignoreRelease; return .end
        default: return .none
        }
    }
    mutating func hold() -> Action {
        guard mode == .pending else { return .none }
        mode = .held; return .begin
    }
    mutating func release(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Action {
        switch mode {
        case .pending: mode = .toggled; lastTap = time; return .begin
        case .held: mode = .idle; return .end
        case .ignoreRelease: mode = .idle; return .none
        default: return .none
        }
    }
    mutating func cancelPending() { if mode == .pending { mode = .ignoreRelease } }
    mutating func reset() { mode = .idle; lastTap = nil }
}
struct TextRule: Codable, Identifiable {
    var id = UUID()
    var spoken: String
    var written: String
}
struct Preferences: Codable {
    var vocabulary = [String]()
    var corrections: [TextRule] = []
    var snippets: [TextRule] = []
    var scratchpad = ""
    var saveHistory = false
    var translateToEnglish: Bool? = nil
    var speechModel: String? = nil
    var homeServerForSpeech: Bool? = nil
    var voiceLearning: Bool? = nil
    var automaticTraining: Bool? = nil
    var transcribeWhileRecording: Bool? = nil
    var translates: Bool { translateToEnglish ?? true }
}
struct TranscriptEntry: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var app: String
    var text: String
    var sourceText: String? = nil
    var learningSampleID: UUID? = nil
    var originalText: String? = nil
    var correctedAt: Date? = nil
}
struct TextProcessing {
    static func apply(_ input: String, corrections: [TextRule], snippets: [TextRule]) -> (text: String, fixes: Int) {
        let spoken = input.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if let snippet = snippets.first(where: { $0.spoken.caseInsensitiveCompare(spoken) == .orderedSame }) { return (snippet.written, 1) }
        var text = input, fixes = 0
        for rule in corrections.sorted(by: { $0.spoken.count > $1.spoken.count }) where !rule.spoken.isEmpty {
            let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: rule.spoken) + "(?![\\p{L}\\p{N}])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches.reversed() {
                if let range = Range(match.range, in: text), String(text[range]) != rule.written { text.replaceSubrange(range, with: rule.written); fixes += 1 }
            }
        }
        return (text, fixes)
    }
}

struct TextDelivery {
    static func supportsUnexposedEditor(bundleID: String) -> Bool {
        // OneNote's custom page editor does not consistently expose an editable AX field.
        ["com.openai.chat", "com.openai.chatgpt", "com.openai.codex", "com.local.codexpp", "com.microsoft.onenote.mac"].contains(bundleID.lowercased())
    }
    static func canPaste(role: String, editable: Bool, selectionSettable: Bool) -> Bool {
        ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"].contains(role) || editable || selectionSettable
    }
}
