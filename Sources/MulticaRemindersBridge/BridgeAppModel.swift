#if os(macOS)
import AppKit
import BridgeCore
import Foundation
import Network
import ServiceManagement

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
    @Published var workspaces: [WorkspaceOption] = []
    @Published var runAtLogin = false

    private var pollTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
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

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.syncNow() }
        }
    }

    deinit {
        pollTask?.cancel()
        networkMonitor.cancel()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
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
        await testConnection(loadWorkspaceList: true)
        await refreshReminderPermission()
        await syncNow()
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
        connectionStatus = "Opening browser sign-in…"
        do {
            let source = makeCliSource()
            try await source.login()
            connectionStatus = try await source.authStatus()
            await loadWorkspaces()
            saveConfiguration()
        } catch {
            connectionStatus = "Disconnected"
            lastError = String(describing: error)
            await BridgeLogger.shared.write("Multica login failed: \(error)")
        }
    }

    func testConnection(loadWorkspaceList: Bool = false) async {
        lastError = nil
        do {
            let source = makeCliSource()
            let version = try await source.version()
            let auth = try await source.authStatus()
            connectionStatus = "Connected · \(version.split(separator: "\n").first.map(String.init) ?? "Multica")\n\(auth)"
            if loadWorkspaceList { await loadWorkspaces() }
        } catch {
            connectionStatus = "Disconnected"
            lastError = String(describing: error)
        }
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
        guard let value = workspaces.first(where: { $0.id == id }) else { return }
        configuration.workspaceID = value.id
        configuration.workspaceSlug = value.slug
        saveConfiguration()
    }

    func refreshReminderPermission() async {
        do {
            let sink = EventKitReminderSink(configuration: configuration)
            let granted = try await sink.requestAccess()
            reminderPermissionStatus = granted ? "Allowed" : "Denied"
        } catch {
            reminderPermissionStatus = "Denied"
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
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            saveConfiguration()
            let db = try BridgeDatabase(path: BridgePaths.databaseURL.path)
            try db.migrate()
            let sink = EventKitReminderSink(configuration: configuration)
            _ = try await sink.requestAccess()
            let engine = SyncEngine(source: makeCliSource(), sink: sink, persistence: db, configuration: configuration)
            let summary = try await engine.sync()
            lastSyncSummary = summary
            lastError = summary.errors.isEmpty ? nil : summary.errors.joined(separator: "\n")
            await BridgeLogger.shared.write("Sync fetched=\(summary.fetchedIssues) upserted=\(summary.createdOrUpdated) resolved=\(summary.resolved) errors=\(summary.errors.count)")
        } catch {
            lastError = String(describing: error)
            await BridgeLogger.shared.write("Sync failed: \(error)")
        }
    }

    func setRunAtLogin(_ enabled: Bool) {
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
