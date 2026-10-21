import Foundation

// Converts individual Hindi words, never asks a model to rewrite a sentence.
// Existing English, whitespace, punctuation, and word order stay under app control.
enum Hinglish {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    static let common: [String: String] = [
        "कि":"ki", "तुम्हें":"tumhe", "तुम्हे":"tumhe", "वाले":"wale", "वाली":"wali", "वाला":"wala", "कौन":"kaun", "सा":"sa", "इतनी":"itni", "इतना":"itna", "तेज":"tez", "बोलने":"bolne", "उसकी":"uski", "उससे":"usse", "उसे":"use", "पा":"pa", "तोह":"toh",
        "रिकॉर्डिंग":"recording", "रेकॉर्डिंग":"recording", "माइक्रोफोन":"microphone", "माइक्रोफ़ोन":"microphone", "स्पीड":"speed", "ट्रांसलेशन":"translation", "स्पेलिंग":"spelling", "प्रोजेक्ट":"project", "एक्जैक्टली":"exactly", "क्लीयरली":"clearly", "क्लियरली":"clearly",

        "अपने":"apne", "अंदर":"andar", "इसको":"isko", "उसको":"usko", "आएगी":"aayegi", "वोकैबुलरी":"vocabulary", "वोकैब्युलरी":"vocabulary", "डिक्शनरी":"dictionary", "आइडेंटिफाई":"identify", "ट्रांसक्राइब":"transcribe", "ट्रांसलेट":"translate", "यूज":"use", "यूज़":"use",
        "मोस्टली":"mostly", "मोस्ट्ली":"mostly", "मोस्ली":"mostly", "मोसली":"mostly", "जो":"joh", "आ":"aa", "जाएगी":"jaayegi", "जायेगी":"jaayegi", "जाएगा":"jaayega", "समझ":"samajh",
        "कोई":"koi", "नया":"naya", "चाहूँगा":"chahunga", "चाहूंगा":"chahunga", "बोलते":"bolte", "मिलते":"milte", "लगता":"lagta", "लगती":"lagti", "लगते":"lagte", "सकते":"sakte",
        "अगर":"agar", "सही":"sahi", "देखता":"dekhta", "कहूँगा":"kahunga", "कहूंगा":"kahunga", "होगा":"hoga", "होता":"hota", "जाना":"jana",
        "चलो":"chalo", "देखते":"dekhte", "देखना":"dekhna", "देख":"dekh", "हैं":"hain", "है":"hai",
        "कैसा":"kaisa", "कैसे":"kaise", "कैसी":"kaisi", "काम":"kaam", "कर":"kar", "करना":"karna",
        "करते":"karte", "करता":"karta", "करती":"karti", "किया":"kiya", "रहा":"raha", "रही":"rahi",
        "रहे":"rahe", "ये":"ye", "यह":"yeh", "वो":"wo", "वह":"woh", "कल":"kal", "आज":"aaj",
        "मुझे":"mujhe", "मेरा":"mera", "मेरी":"meri", "मेरे":"mere", "मैं":"main", "में":"mein",
        "हम":"hum", "हमारा":"hamara", "आप":"aap", "आपका":"aapka", "तुम":"tum", "तुम्हारा":"tumhara",
        "को":"ko", "के":"ke", "की":"ki", "का":"ka", "से":"se", "ने":"ne", "पर":"par",
        "और":"aur", "या":"ya", "लेकिन":"lekin", "तो":"to", "भी":"bhi", "ही":"hi", "नहीं":"nahi",
        "हाँ":"haan", "हां":"haan", "जी":"ji", "क्या":"kya", "क्यों":"kyun", "कब":"kab", "कहाँ":"kahan",
        "कहां":"kahan", "कुछ":"kuch", "बहुत":"bahut", "अच्छा":"achha", "अच्छी":"achhi", "ठीक":"theek",
        "अभी":"abhi", "फिर":"phir", "बाद":"baad", "पहले":"pehle", "लिए":"liye", "एक":"ek",
        "इस":"is", "इसका":"iska", "उस":"us", "उसका":"uska", "इसमें":"ismein", "उसमें":"usmein",
        "हो":"ho", "हूँ":"hoon", "हूं":"hoon", "था":"tha", "थी":"thi", "थे":"the",
        "चाहिए":"chahiye", "चाहता":"chahta", "चाहती":"chahti", "सकता":"sakta", "सकती":"sakti",
        "भेजना":"bhejna", "भेज":"bhej", "बना":"bana", "बनाना":"banana", "लिख":"likh", "लिखना":"likhna",
        "बोल":"bol", "बोलना":"bolna", "सुन":"sun", "गया":"gaya", "गई":"gayi",
        "दिया":"diya", "देना":"dena", "दो":"do", "बस":"bas", "सब":"sab", "ऐसे":"aise", "वैसे":"waise",
        "अपडेट":"update", "क्लाइंट":"client", "ऐप":"app", "एप":"app", "ऐप्स":"apps", "एप्स":"apps",
        "ईमेल":"email", "मेल":"mail", "मैसेज":"message", "फाइल":"file", "फ़ाइल":"file", "फोल्डर":"folder",
        "मीटिंग":"meeting", "कॉपी":"copy", "पेस्ट":"paste", "टेस्ट":"test", "टेक्स्ट":"text",
        "इंग्लिश":"English", "हिंदी":"Hindi", "हिन्दी":"Hindi", "हिंग्लिश":"Hinglish", "लोकल":"local",
        "मॉडल":"model", "सेटिंग्स":"settings", "शॉर्टकट":"shortcut", "फ़ॉन्ट":"font", "फॉन्ट":"font"
    ]
    static let pattern = "[\\u0900-\\u0963\\u0971-\\u097F]+"
    static func words(in input: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: pattern)
        var seen = Set<String>()
        return regex.matches(in: input, range: NSRange(input.startIndex..., in: input)).compactMap {
            guard let range = Range($0.range, in: input) else { return nil }
            let word = String(input[range])
            return seen.insert(word).inserted ? word : nil
        }
    }
    static func replace(_ input: String, spellings: [String: String]) throws -> String {
        var result = input
        let regex = try! NSRegularExpression(pattern: pattern)
        for match in regex.matches(in: input, range: NSRange(input.startIndex..., in: input)).reversed() {
            guard let range = Range(match.range, in: result), let word = spellings[String(result[range])],
                  word.range(of: "^[A-Za-z][A-Za-z'-]{0,79}$", options: .regularExpression) != nil else {
                throw Failure(message: "Hinglish spelling was incomplete. Nothing was pasted; try again.")
            }
            result.replaceSubrange(range, with: word)
        }
        result = result.replacingOccurrences(of: "।", with: ".").replacingOccurrences(of: "॥", with: ".")
        for (i, digit) in "०१२३४५६७८९".enumerated() { result = result.replacingOccurrences(of: String(digit), with: String(i)) }
        return result
    }
    static func convertOnHomeServer(
        _ input: String,
        cacheURL: URL,
        job: ProcessingJob? = nil,
        romanize: ([String]) throws -> [String: String]
    ) throws -> String {
        try job?.check()
        let needed = words(in: input)
        guard !needed.isEmpty else { return try replace(input, spellings: [:]) }
        var cache = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: cacheURL))) ?? [:]
        var spellings = cache.merging(common) { _, standard in standard }
        let missing = needed.filter { spellings[$0] == nil }
        if !missing.isEmpty {
            guard missing.count <= 512 else {
                throw Failure(message: "Dictation is too long to spell in one pass. Original text is available below.")
            }
            let converted = try romanize(missing)
            guard Set(converted.keys) == Set(missing) else {
                throw Failure(message: "Hinglish conversion could not finish. Original text is available below.")
            }
            for word in missing { _ = try replace(word, spellings: converted) }
            spellings.merge(converted) { _, new in new }
            cache.merge(converted) { _, new in new }
            try? JSONEncoder().encode(cache).write(to: cacheURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheURL.path)
        }
        try job?.check()
        return try replace(input, spellings: spellings)
    }
    // Character-level IndicXlit replaces the general-purpose chat model.
    static func convert(_ input: String, cacheURL: URL, job: ProcessingJob? = nil) throws -> String {
        try job?.check()
        let needed = words(in: input)
        guard !needed.isEmpty else { return try replace(input, spellings: [:]) }
        var cache = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: cacheURL))) ?? [:]
        var spellings = cache.merging(common) { _, standard in standard }
        let missing = needed.filter { spellings[$0] == nil }
        if !missing.isEmpty {
            let python = AppResources.python("xlit")
            let bundled = Bundle.main.resourceURL?.appendingPathComponent("Xlit/romanize.py")
            let source = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("xlit/romanize.py")
            let script = bundled.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil } ?? source
            guard FileManager.default.isExecutableFile(atPath: python.path), FileManager.default.fileExists(atPath: script.path) else {
                throw Failure(message: "Local Hinglish model is missing. Your original transcript is available below.")
            }
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("localvoice-xlit-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: temporary) }
            let inputURL = temporary.appendingPathComponent("input.json"), outputURL = temporary.appendingPathComponent("output.json")
            let bytes = try JSONEncoder().encode(missing)
            guard missing.count <= 512 else { throw Failure(message: "Dictation is too long to spell in one pass. Original text is available below.") }
            FileManager.default.createFile(atPath: inputURL.path, contents: bytes, attributes: [.posixPermissions: 0o600])
            FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
            let incoming = try FileHandle(forReadingFrom: inputURL), outgoing = try FileHandle(forWritingTo: outputURL)
            defer { try? incoming.close(); try? outgoing.close() }
            let process = Process()
            process.environment = AppResources.environment()
            process.executableURL = python; process.arguments = ["-B", script.path, AppResources.asset("indicxlit").path]
            process.standardInput = incoming; process.standardOutput = outgoing; process.standardError = FileHandle.nullDevice
            let control = job ?? ProcessingJob(timeout: 25)
            do { try control.run(process, timeout: 25) }
            catch { throw Failure(message: control.isCancelled ? "Hinglish conversion cancelled or timed out. Original text is available below." : "Hinglish model could not start. Original text is available below.") }
            let response = try Data(contentsOf: outputURL)
            guard process.terminationStatus == 0, let converted = try? JSONDecoder().decode([String: String].self, from: response), Set(converted.keys) == Set(missing) else {
                throw Failure(message: "Hinglish conversion could not finish. Original text is available below.")
            }
            for word in missing { _ = try replace(word, spellings: converted) }
            spellings.merge(converted) { _, new in new }; cache.merge(converted) { _, new in new }
            try? JSONEncoder().encode(cache).write(to: cacheURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheURL.path)
        }
        try job?.check()
        return try replace(input, spellings: spellings)
    }
}
