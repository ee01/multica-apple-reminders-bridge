import Foundation

struct CLILocator {
    static func locate() -> String {
        let candidates = [
            "/opt/homebrew/bin/multica",
            "/usr/local/bin/multica",
            "/usr/bin/multica"
        ]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for directory in path.split(separator: ":") {
                let candidate = String(directory) + "/multica"
                if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
            }
        }
        return "/opt/homebrew/bin/multica"
    }
}
