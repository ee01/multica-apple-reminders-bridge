#if os(macOS)
import AppKit

/// Menu-bar agent apps (`LSUIElement`) do not come forward on their own.
/// Temporarily become a regular app while a user window is open, then go back.
@MainActor
enum AppWindowPresenter {
    private static var closeObservers: [ObjectIdentifier: NSObjectProtocol] = [:]

    static func becomeRegularApp() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    static func raise(_ window: NSWindow) {
        becomeRegularApp()
        window.collectionBehavior.insert(.moveToActiveSpace)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        observeClose(window)
    }

    static func restoreAccessoryIfNoWindows() {
        let hasUserWindow = NSApp.windows.contains { isUserWindow($0) && ($0.isVisible || $0.isMiniaturized) }
        if !hasUserWindow, NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private static func isUserWindow(_ window: NSWindow) -> Bool {
        guard window.canBecomeKey else { return false }
        let name = String(describing: type(of: window))
        if name.contains("StatusBar") || name.contains("NSStatusBar") || name.contains("MenuBarExtra") {
            return false
        }
        return window.level == .normal
    }

    private static func observeClose(_ window: NSWindow) {
        let id = ObjectIdentifier(window)
        guard closeObservers[id] == nil else { return }
        closeObservers[id] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            Task { @MainActor in
                if let observer = closeObservers.removeValue(forKey: id) {
                    NotificationCenter.default.removeObserver(observer)
                }
                DispatchQueue.main.async {
                    restoreAccessoryIfNoWindows()
                }
            }
        }
    }
}
#endif
