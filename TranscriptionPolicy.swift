import Foundation

// Capture these settings when recording begins. Recovery stores only routing
// and output settings, never the scratchpad, transcript, or dictionary.
struct DictationConfiguration: Codable, Equatable {
    var translateToEnglish: Bool
    var speechModel: String?
    var preferHomeServer: Bool

    init(preferences: Preferences, preferHomeServer: Bool) {
        translateToEnglish = preferences.translates
        speechModel = preferences.speechModel
        self.preferHomeServer = preferHomeServer
    }

    func applying(to preferences: Preferences) -> Preferences {
        var result = preferences
        result.translateToEnglish = translateToEnglish
        result.speechModel = speechModel
        result.homeServerForSpeech = preferHomeServer
        return result
    }

    var homeServerModel: String? {
        guard preferHomeServer else { return nil }
        if translateToEnglish || speechModel == "whisper" { return "whisper" }
        return speechModel == "qwen-1.7" ? "qwen-1.7" : "qwen-0.6"
    }
}

struct RecordingRecoveryMetadata: Codable {
    var version = 1
    var configuration: DictationConfiguration
    var createdAt = Date()
}

enum TranscriptionPolicy {
    // Based on OpenWhispr's duration-scaled budgets, with a bounded local cap.
    static func overallTimeout(seconds: Double, remote: Bool) -> TimeInterval {
        let duration = seconds.isFinite && seconds > 0 ? seconds : 0
        return min(1800, max(remote ? 350 : 180, duration * 6 + 60))
    }

    static func requestTimeout(seconds: Double) -> TimeInterval {
        min(180, max(40, (seconds.isFinite && seconds > 0 ? seconds : 0) * 4 + 10))
    }

    static func vocabulary(_ terms: [String]) -> [String] {
        var seen = Set<String>()
        return terms.compactMap { term in
            let clean = String(term.trimmingCharacters(in: .whitespacesAndNewlines).prefix(128))
            guard !clean.isEmpty, seen.insert(clean.lowercased()).inserted else { return nil }
            return clean
        }.prefix(60).map { $0 }
    }

    static func prompt(_ terms: [String]) -> String {
        let terms = vocabulary(terms)
        guard !terms.isEmpty else { return "" }
        return String(String.UnicodeScalarView(("Vocabulary: " + terms.joined(separator: ", ")).unicodeScalars.prefix(4096)))
    }
}

// Swift adaptation of OpenWhispr's dictionaryEchoFilter.js. Overlap alone is
// insufficient: short dictations and repeated ordinary words are real speech.
// Keep Unicode marks so Hindi vowel signs remain part of their words.
enum VocabularyEchoGuard {
    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "[^\\p{L}\\p{M}\\p{N}\\s]", with: "", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func isSuspicious(_ text: String, vocabulary: [String]) -> Bool {
        let terms = TranscriptionPolicy.vocabulary(vocabulary).map(normalize).filter { !$0.isEmpty }
        guard !terms.isEmpty else { return false }
        let normalized = normalize(text.replacingOccurrences(of: "^\\s*Vocabulary\\s*:", with: "", options: [.regularExpression, .caseInsensitive]))
        let words = normalized.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return false }
        let dictionaryWords = Set(terms.flatMap { $0.split(separator: " ").map(String.init) })
        let unique = Set(words)
        guard Double(unique.intersection(dictionaryWords).count) / Double(unique.count) >= 0.9 else { return false }
        let counts = Dictionary(grouping: words, by: { $0 })
        if counts.values.contains(where: { $0.count >= 3 }) { return true }
        let delimiters = CharacterSet(charactersIn: ",、，")
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.count <= 30, let last = trimmed.unicodeScalars.last, delimiters.contains(last) { return true }
        guard text.rangeOfCharacter(from: delimiters) != nil, terms.count >= 3 else { return false }
        let sequence = terms.enumerated().flatMap { index, term in
            term.split(separator: " ").map { (word: String($0), term: index) }
        }
        guard words.count <= sequence.count else { return false }
        for start in 0...(sequence.count - words.count) {
            if zip(words, sequence[start..<(start + words.count)]).allSatisfy({ $0 == $1.word }),
               sequence[start + words.count - 1].term - sequence[start].term + 1 >= 3 { return true }
        }
        return false
    }
}

struct RecognitionFailure: LocalizedError {
    let message: String
    var partialText = ""
    var errorDescription: String? { message }
}
