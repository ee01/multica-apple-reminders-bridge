#if os(macOS)
import AppKit
import BridgeCore
import Foundation
import Network
import ServiceManagement
import SwiftUI

struct WorkspaceOption: Identifiable, Hashable {
    let id: String
    let name: String
    let slug: String?
    var displayName: String { slug.map { "\(name) (\($0))" } ?? name }
}

@MainActor
final class BridgeAppModel: ObservableObject {
    @Published var configuration: BridgeConfiguration
    @Published var connectionStatus = "Not checked"
    @Published var reminderPermissionStatus = "Not checked"
    @Published var lastSyncSummary: SyncSummary?
    @Published var lastError: String?
    @Published var isSyncing = false
    @Published var isConnecting = false
    @Published var isAuthenticated = false
    @Published var workspaces: [WorkspaceOption] = []
    @Published var projects: [MulticaProject] = []
    @Published var agents: [MulticaAgent] = []
    @Published var appleReminderLists: [String] = []
    @Published var runAtLogin = false
    @Published var isLoadingCatalog = false
    @Published var catalogError: String?

    var checklist: SetupChecklist {
        SetupChecklist(
            isAuthenticated: isAuthenticated,
            hasWorkspace: configuration.workspaceID?.isEmpty == false,
            hasRemindersAccess: reminderPermissionStatus == "Allowed"
        )
    }

    var menuBarSymbol: String {
        checklist.isReadyToSync ? "checklist.checked" : "exclamationmark.circle"
    }

    private var pollTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var activateObserver: NSObjectProtocol?
    private var didOfferOnboarding = false
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "ai.personal.multica-reminders-bridge.network")
    private var networkMonitorStarted = false
    private let runner = ProcessCommandRunner()

    init() {
        try? BridgePaths.ensureDirectories()
        if let loaded = try? BridgeConfiguration.load(from: BridgePaths.configurationURL) {
            configuration = loaded
        } else {
            configuration = BridgeConfiguration(multicaCLIPath: CLILocator.locate())
            try? configuration.save(to: BridgePaths.configurationURL)
        }
        runAtLogin = SMAppService.mainApp.status == .enabled
        applyRunAtLoginPreference()
        reminderPermissionStatus = EventKitReminderSink.authorizationLabel
        appleReminderLists = EventKitReminderSink.writableListNames()

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.syncNow() }
        }
        activateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.handleAppBecameActive() }
        }
        Task { @MainActor [weak self] in
            self?.start()
        }
    }

    deinit {
        pollTask?.cancel()
        networkMonitor.cancel()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if let activateObserver { NotificationCenter.default.removeObserver(activateObserver) }
    }

    func start() {
        guard pollTask == nil else { return }
        startNetworkMonitorIfNeeded()
        pollTask = Task { [weak self] in
            guard let self else { return }
            await self.bootstrap()
            while !Task.isCancelled {
                let seconds = max(30, self.configuration.pollIntervalSeconds)
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                if Task.isCancelled { break }
                await self.syncNow()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func bootstrap() async {
        reminderPermissionStatus = EventKitReminderSink.authorizationLabel
        loadAppleReminderLists()
        await testConnection(loadWorkspaceList: true)
        if !checklist.isReadyToSync, !didOfferOnboarding {
            didOfferOnboarding = true
            openOnboardingWindow()
        }
        if checklist.isReadyToSync {
            await syncNow()
        }
    }

    func saveConfiguration() {
        do {
            try BridgePaths.ensureDirectories()
            try configuration.save(to: BridgePaths.configurationURL)
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
    }

    func connectMultica() async {
        lastError = nil
        isConnecting = true
        connectionStatus = "Waiting for browser sign-in…"
        defer { isConnecting = false }

        let loginTask = Task { try await makeCliSource().login() }
        let pollTask = Task { await self.pollForAuthentication() }
        do {
            _ = try await loginTask.value
            pollTask.cancel()
            _ = await refreshAuthentication(loadCatalogIfPossible: true)
        } catch {
            pollTask.cancel()
            if isAuthenticated {
                lastError = nil
                return
            }
            if await refreshAuthentication(loadCatalogIfPossible: true) {
                lastError = nil
                return
            }
            connectionStatus = "Disconnected"
            lastError = String(describing: error)
            await BridgeLogger.shared.write("Multica login failed: \(error)")
        }
    }

    func testConnection(loadWorkspaceList: Bool = false) async {
        lastError = nil
        if await refreshAuthentication(loadCatalogIfPossible: loadWorkspaceList) { return }
        connectionStatus = "Disconnected"
        if !checklist.isReadyToSync { return }
        lastError = "Multica is not signed in. Use Connect Multica, then return here — Bridge will pick up the session automatically."
    }

    func loadWorkspaces() async {
        do {
            let values = try await makeCliSource().listWorkspaces()
            workspaces = values.map { WorkspaceOption(id: $0.id, name: $0.name, slug: $0.slug) }
            if configuration.workspaceID == nil, workspaces.count == 1, let only = workspaces.first {
                selectWorkspace(only.id)
            }
        } catch {
            lastError = String(describing: error)
        }
    }

    func selectWorkspace(_ id: String) {
        if id.isEmpty {
            configuration.workspaceID = nil
            configuration.workspaceSlug = nil
            projects = []
            agents = []
            saveConfiguration()
            return
        }
        guard let value = workspaces.first(where: { $0.id == id }) else { return }
        configuration.workspaceID = value.id
        configuration.workspaceSlug = value.slug
        saveConfiguration()
        Task { @MainActor [weak self] in await self?.loadCatalog() }
    }

    func loadCatalog() async {
        guard configuration.workspaceID != nil else {
            projects = []
            agents = []
            catalogError = nil
            return
        }
        isLoadingCatalog = true
        defer { isLoadingCatalog = false }
        let source = makeCliSource()
        var loadedProjects: [MulticaProject] = []
        var loadedAssignees: [MulticaAgent] = []
        var errors: [String] = []

        do {
            loadedProjects = try await source.listProjects()
        } catch {
            errors.append("projects: \(error)")
        }
        do {
            loadedAssignees.append(contentsOf: try await source.listAgents())
        } catch {
            errors.append("agents: \(error)")
        }
        do {
            loadedAssignees.append(contentsOf: try await source.listSquads())
        } catch {
            // Squads are optional. Older CLIs or empty workspaces should not block agent pickers.
        }

        projects = loadedProjects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        agents = loadedAssignees.sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind == .agent }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        catalogError = errors.isEmpty ? nil : errors.joined(separator: "\n")
        applyDefaultAssigneeIfNeeded()
    }

    /// New users should not have to open Settings to pick an assignee.
    private func applyDefaultAssigneeIfNeeded() {
        guard configuration.defaultAgentID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false else { return }
        guard let preferred = agents.preferredDefaultAssignee() else { return }
        setDefaultAgent(preferred.id)
        saveConfiguration()
    }

    func setDefaultProject(_ id: String) {
        configuration.defaultProjectID = id.isEmpty ? nil : id
        configuration.defaultProjectName = projects.first(where: { $0.id == id })?.name
    }

    func setDefaultAgent(_ id: String) {
        configuration.defaultAgentID = id.isEmpty ? nil : id
        configuration.defaultAgentName = agents.first(where: { $0.id == id })?.name
    }

    func addProjectRoute() {
        configuration.projectRoutes.append(ProjectRoute(appleListName: "", mirrorMode: configuration.defaultMirrorMode))
    }

    func loadAppleReminderLists() {
        appleReminderLists = EventKitReminderSink.writableListNames()
    }

    func refreshAppleReminderLists() async {
        do {
            let sink = EventKitReminderSink(configuration: configuration)
            _ = try await sink.requestAccess()
        } catch {}
        loadAppleReminderLists()
    }

    func removeProjectRoute(id: String) {
        configuration.projectRoutes.removeAll { $0.id == id }
        saveConfiguration()
    }

    func refreshReminderPermission(prompt: Bool = true) async {
        reminderPermissionStatus = EventKitReminderSink.authorizationLabel
        guard prompt || EventKitReminderSink.hasFullAccess else { return }
        do {
            let sink = EventKitReminderSink(configuration: configuration)
            let granted = try await sink.requestAccess()
            reminderPermissionStatus = granted ? "Allowed" : "Denied"
            lastError = nil
            await refreshAppleReminderLists()
        } catch {
            reminderPermissionStatus = EventKitReminderSink.authorizationLabel
            lastError = String(describing: error)
        }
    }

    func createTestReminder() async {
        do {
            let sink = EventKitReminderSink(configuration: configuration)
            _ = try await sink.createTestReminder(
                title: "Multica Bridge Test",
                notes: "Apple Reminders Bridge 已连接。你可以删除这条测试提醒。"
            )
            reminderPermissionStatus = "Allowed"
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
    }

    func syncNow() async {
        guard checklist.isReadyToSync else { return }
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            saveConfiguration()
            await BridgeLogger.shared.write("Sync starting")
            let db = try BridgeDatabase(path: BridgePaths.databaseURL.path)
            try db.migrate()
            let sink = EventKitReminderSink(configuration: configuration)
            _ = try await sink.requestAccess()
            let engine = SyncEngine(source: makeCliSource(), sink: sink, persistence: db, configuration: configuration)
            let summary = try await engine.sync()
            lastSyncSummary = summary
            lastError = summary.errors.isEmpty ? nil : summary.errors.joined(separator: "\n")
            loadAppleReminderLists()
            await BridgeLogger.shared.write("Sync fetched=\(summary.fetchedIssues) scanned=\(summary.scannedRequests) dispatched=\(summary.dispatchedRequests) main=\(summary.mainCreatedOrUpdated) human=\(summary.humanActionsCreatedOrUpdated) resolved=\(summary.resolved) errors=\(summary.errors.count)")
            for error in summary.errors {
                await BridgeLogger.shared.write("Sync error: \(error)")
            }
        } catch {
            lastError = String(describing: error)
            await BridgeLogger.shared.write("Sync failed: \(error)")
        }
    }

    func setRunAtLogin(_ enabled: Bool) {
        configuration.runAtLoginEnabled = enabled
        saveConfiguration()
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            runAtLogin = SMAppService.mainApp.status == .enabled
            lastError = nil
        } catch {
            runAtLogin = SMAppService.mainApp.status == .enabled
            lastError = "Run at Login: \(error)"
        }
    }

    private func applyRunAtLoginPreference() {
        if configuration.runAtLoginEnabled, SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        }
        runAtLogin = SMAppService.mainApp.status == .enabled
    }

    func openReviewBoard() {
        guard var components = URLComponents(string: configuration.appBaseURL) else { return }
        var path = components.path
        if let slug = configuration.workspaceSlug, !slug.isEmpty { path += "/\(slug)" }
        path += "/issues"
        components.path = path
        components.queryItems = [URLQueryItem(name: "status", value: "in_review")]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }

    func openDiagnosticsFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([BridgePaths.diagnosticsURL])
    }

    func openSettingsWindow() {
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView(model: self))
            let window = NSWindow(contentViewController: controller)
            window.title = "Settings"
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 760, height: 720))
            window.minSize = NSSize(width: 720, height: 640)
            window.center()
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.settingsWindow = nil
                    AppWindowPresenter.restoreAccessoryIfNoWindows()
                }
            }
            settingsWindow = window
        }
        if let window = settingsWindow {
            AppWindowPresenter.raise(window)
        }
    }

    func openOnboardingWindow() {
        if onboardingWindow == nil {
            let controller = NSHostingController(rootView: OnboardingView(model: self))
            let window = NSWindow(contentViewController: controller)
            window.title = "Set Up Bridge"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 540, height: 560))
            window.center()
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.onboardingWindow = nil
                    AppWindowPresenter.restoreAccessoryIfNoWindows()
                }
            }
            onboardingWindow = window
        }
        if let window = onboardingWindow {
            AppWindowPresenter.raise(window)
        }
    }

    func closeOnboardingWindow() {
        onboardingWindow?.performClose(nil)
    }

    @discardableResult
    func refreshAuthentication(loadCatalogIfPossible: Bool = false) async -> Bool {
        do {
            let source = makeCliSource()
            let version = try await source.version()
            let auth = try await source.authStatus()
            isAuthenticated = true
            let versionLine = version.split(separator: "\n").first.map(String.init) ?? "Multica"
            connectionStatus = "Connected · \(versionLine)\n\(auth)"
            if loadCatalogIfPossible {
                await loadWorkspaces()
                await loadCatalog()
            }
            lastError = nil
            return true
        } catch {
            isAuthenticated = false
            return false
        }
    }

    private func pollForAuthentication() async {
        for _ in 0..<90 {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled { return }
            if await refreshAuthentication(loadCatalogIfPossible: true) { return }
        }
    }

    private func handleAppBecameActive() async {
        guard isConnecting || !isAuthenticated else { return }
        if await refreshAuthentication(loadCatalogIfPossible: true) {
            lastError = nil
        }
    }

    private func startNetworkMonitorIfNeeded() {
        guard !networkMonitorStarted else { return }
        networkMonitorStarted = true
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in
                await self?.syncNow()
            }
        }
        networkMonitor.start(queue: networkQueue)
    }

    private func makeCliSource() -> MulticaCliSource<ProcessCommandRunner> {
        MulticaCliSource(configuration: configuration, runner: runner)
    }
}
#endif
