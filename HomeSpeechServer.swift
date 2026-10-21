import Foundation

// Public source distribution supports local processing only.
// Personal private-server configuration is deliberately not loaded.
struct HomeSpeechServerConfiguration {
    let endpoint: URL
    let token: String
    static func load(in directory: URL) -> HomeSpeechServerConfiguration? { nil }
    static func isConfigured(in directory: URL) -> Bool { false }
    func url(path: String) -> URL {
        URL(string: path, relativeTo: endpoint)!.absoluteURL
    }
}
