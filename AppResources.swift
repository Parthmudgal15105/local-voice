import Foundation

// Release bundles carry read-only engines/models. User settings and recordings
// always stay in Application Support, outside the application signature.
enum AppResources {
    static let userData = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Local Voice", isDirectory: true)
    static func asset(_ relative: String, userDirectory: URL = userData) -> URL {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Models/" + relative), FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        return userDirectory.appendingPathComponent(relative)
    }
    static func python(_ engine: String) -> URL {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Runtime/" + engine + "/bin/python3"), FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        return userData.appendingPathComponent(engine == "asr" ? "asr-env/bin/python" : "xlit-env/bin/python")
    }
    static func environment() -> [String: String] {
        var result = ProcessInfo.processInfo.environment
        result.removeValue(forKey: "PYTHONHOME"); result.removeValue(forKey: "PYTHONPATH")
        result["PYTHONNOUSERSITE"] = "1"; result["PYTHONDONTWRITEBYTECODE"] = "1"
        result["HF_HUB_OFFLINE"] = "1"; result["TRANSFORMERS_OFFLINE"] = "1"
        result["LOCALVOICE_LEARNING_DIRECTORY"] = userData.appendingPathComponent("Learning").path
        result["LOCALVOICE_QWEN_MODEL"] = asset("asr-models/Qwen3-ASR-0.6B-8bit").path
        return result
    }
}
