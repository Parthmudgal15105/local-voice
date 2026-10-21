import Foundation

struct Session: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let seconds: Double
    let words: Int
    let app: String
}

struct RankedExpression: Identifiable {
    var id: String { text }
    let text: String
    let count: Int
    let dictations: Int
}

struct DictationFingerprint {
    let documents: Int
    let words: Int
    let uniqueWords: Int
    let vocabulary: [RankedExpression]
    let phrases: [RankedExpression]
    let expressions: [RankedExpression]

    // Linked history and learning entries describe the same dictation. Prefer the edited history.
    static func corpus(history: [TranscriptEntry], samples: [LearningSample]) -> [String] {
        let linked = Set(history.compactMap(\.learningSampleID))
        return history.map(\.text) + samples.filter { !linked.contains($0.id) }.map(\.corrected)
    }
    static func tokens(_ text: String) -> [String] {
        let normalized = text.lowercased().replacingOccurrences(of: "’", with: "'")
        let regex = try! NSRegularExpression(pattern: "[\\p{L}\\p{M}]+(?:'[\\p{L}\\p{M}]+)*")
        return regex.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)).compactMap {
            Range($0.range, in: normalized).map { String(normalized[$0]) }
        }
    }
    private static let stopwords = Set("a an the i i'm i've i'll i'd me my mine myself we we're we've our ours you you're you've your yours he his him himself she her hers herself it it's its they they're their them this that that's these those am is are was were be been being have has had do does did don't doesn't didn't can can't could would should will won't may might must and or but because if so as at by for from in into of on onto to with without about than then there here where when what which who how why not no yes all any each every some just very really also too more most much many such only even still already now well get got getting going go goes gone make makes made like want wants wanted need needs needed let let's okay ok please know think thing things something anything everything nothing one two time hain hai ho hoon hun hu main mein mai mujhe mera meri mere hum hume tum tumhe aap apna apni apne ye yeh woh wo vo jo joh aur ya lekin ki ke ka ko se par pe toh to bhi hi nahi nahin na kya kyun kyu kaise kab ab bas bahut kuch ek kar karo karna karne raha rahi rahe tha thi the hoga hogi liye wale wali waala wala haii haan chahiye ja jaa jaane gaya gayi sakta sakte toh".split(separator: " ").map(String.init))
    private static let expressionList = ["i think", "i mean", "you know", "kind of", "sort of", "basically", "actually", "literally", "honestly", "maybe", "mostly", "matlab", "basically", "mujhe lagta hai"]

    init(texts: [String]) {
        let retained = texts.filter { !Self.tokens($0).isEmpty }
        let docs = retained.map(Self.tokens)
        documents = docs.count
        let flat = docs.flatMap { $0 }
        words = flat.count
        uniqueWords = Set(flat).count
        var counts: [String: Int] = [:], appearances: [String: Int] = [:]
        var phraseCounts: [String: Int] = [:], phraseDocs: [String: Int] = [:]
        var expressionCounts: [String: Int] = [:], expressionDocs: [String: Int] = [:]
        for (index, doc) in docs.enumerated() {
            let content = doc.filter { $0.count > 2 && !Self.stopwords.contains($0) }
            for word in content { counts[word, default: 0] += 1 }
            for word in Set(content) { appearances[word, default: 0] += 1 }
            var seenPhrases = Set<String>(), seenExpressions = Set<String>()
            let sentences = retained[index].components(separatedBy: CharacterSet(charactersIn: ".!?।;\n")).map(Self.tokens)
            for sentence in sentences {
                for length in 2...3 where sentence.count >= length {
                    for start in 0...(sentence.count - length) {
                        let chunk = Array(sentence[start..<(start + length)])
                        // Keep the original word order, including function words inside a phrase.
                        guard !Self.stopwords.contains(chunk.first!), !Self.stopwords.contains(chunk.last!) else { continue }
                        let phrase = chunk.joined(separator: " ")
                        phraseCounts[phrase, default: 0] += 1; seenPhrases.insert(phrase)
                    }
                }
                for expression in Set(Self.expressionList) {
                    let needle = Self.tokens(expression)
                    guard sentence.count >= needle.count else { continue }
                    for start in 0...(sentence.count - needle.count) where Array(sentence[start..<(start + needle.count)]) == needle {
                        expressionCounts[expression, default: 0] += 1; seenExpressions.insert(expression)
                    }
                }
            }
            for phrase in seenPhrases { phraseDocs[phrase, default: 0] += 1 }
            for expression in seenExpressions { expressionDocs[expression, default: 0] += 1 }
        }
        func ranked(_ values: [String: Int], _ docs: [String: Int]) -> [RankedExpression] {
            values.map { RankedExpression(text: $0.key, count: $0.value, dictations: docs[$0.key, default: 0]) }
                .sorted { $0.count == $1.count ? $0.text < $1.text : $0.count > $1.count }
        }
        vocabulary = ranked(counts, appearances)
        phrases = ranked(phraseCounts.filter { phraseDocs[$0.key, default: 0] >= 2 }, phraseDocs)
        expressions = ranked(expressionCounts, expressionDocs)
    }
}

struct DictationActivity {
    struct Day: Identifiable {
        var id: Date { date }
        let date: Date
        let words: Int
    }
    let sessions: [Session]
    let days: [Day]
    let currentWeekWords: Int
    let previousWeekWords: Int
    let peakHour: Int?
    let peakHourCount: Int
    let activeDays: Int
    let longest: Session?
    var words: Int { sessions.reduce(0) { $0 + $1.words } }
    var seconds: Double { sessions.reduce(0) { $0 + max(0, $1.seconds) } }
    var wpm: Int { seconds > 0 ? Int(Double(words) * 60 / seconds) : 0 }
    var averageWords: Int { sessions.isEmpty ? 0 : words / sessions.count }
    var averageSeconds: Int { sessions.isEmpty ? 0 : Int(seconds / Double(sessions.count)) }
    var appUsage: [(String, Int)] {
        Dictionary(grouping: sessions, by: \.app).map { ($0.key, $0.value.reduce(0) { $0 + $1.words }) }
            .sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
    }
    init(sessions all: [Session], rangeDays: Int?, now: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let cutoff = rangeDays.flatMap { calendar.date(byAdding: .day, value: -($0 - 1), to: today) }
        sessions = all.filter { $0.date <= now && (cutoff == nil || $0.date >= cutoff!) }
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -6, to: today)!
        let fourteenDaysAgo = calendar.date(byAdding: .day, value: -13, to: today)!
        currentWeekWords = all.filter { $0.date >= sevenDaysAgo && $0.date <= now }.reduce(0) { $0 + $1.words }
        previousWeekWords = all.filter { $0.date >= fourteenDaysAgo && $0.date < sevenDaysAgo }.reduce(0) { $0 + $1.words }
        let totals = Dictionary(grouping: sessions, by: { calendar.startOfDay(for: $0.date) }).mapValues { $0.reduce(0) { $0 + $1.words } }
        let chartCount = rangeDays ?? min(30, max(14, (sessions.map { calendar.dateComponents([.day], from: $0.date, to: now).day ?? 0 }.max() ?? 0) + 1))
        days = (0..<chartCount).map { index in
            let date = calendar.date(byAdding: .day, value: index - chartCount + 1, to: today)!
            return Day(date: date, words: totals[date, default: 0])
        }
        let hours = Dictionary(grouping: sessions, by: { calendar.component(.hour, from: $0.date) }).mapValues(\.count)
        let peak = hours.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.first
        peakHour = peak?.key; peakHourCount = peak?.value ?? 0
        activeDays = totals.count
        longest = sessions.max { $0.seconds < $1.seconds }
    }
}
