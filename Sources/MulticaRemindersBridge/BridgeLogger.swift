import Foundation

actor BridgeLogger {
    static let shared = BridgeLogger()

    func write(_ message: String) {
        let formatter = ISO8601DateFormatter()
        let line = "[\(formatter.string(from: Date()))] \(sanitize(message))\n"
        do {
            try BridgePaths.ensureDirectories()
            let data = Data(line.utf8)
            if FileManager.default.fileExists(atPath: BridgePaths.diagnosticsURL.path) {
                let handle = try FileHandle(forWritingTo: BridgePaths.diagnosticsURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: BridgePaths.diagnosticsURL, options: .atomic)
            }
        } catch {
            // Diagnostics must never break the bridge.
        }
    }

    private func sanitize(_ value: String) -> String {
        value.replacingOccurrences(of: #"mul_[A-Za-z0-9_-]+"#, with: "mul_[REDACTED]", options: .regularExpression)
    }
}
