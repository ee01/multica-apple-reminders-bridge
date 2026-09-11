import Foundation

struct BridgePaths {
    static let appSupportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("MulticaRemindersBridge", isDirectory: true)
    }()

    static let configurationURL = appSupportDirectory.appendingPathComponent("config.json")
    static let databaseURL = appSupportDirectory.appendingPathComponent("bridge.sqlite")
    static let diagnosticsURL = appSupportDirectory.appendingPathComponent("bridge.log")

    static func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
    }
}
