#if os(macOS)
import SwiftUI

@main
struct MulticaRemindersBridgeApp: App {
    @StateObject private var model = BridgeAppModel()

    var body: some Scene {
        MenuBarExtra("Multica Bridge", systemImage: model.menuBarSymbol) {
            MenuBarView(model: model)
        }
    }
}
#else
import Foundation

@main
enum MulticaRemindersBridgeUnsupportedMain {
    static func main() {
        fputs("MulticaRemindersBridge is a macOS application. Core tests can run on this platform.\n", stderr)
    }
}
#endif
