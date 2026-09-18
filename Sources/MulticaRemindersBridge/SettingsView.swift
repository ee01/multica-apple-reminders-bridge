#if os(macOS)
import BridgeCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: BridgeAppModel

    var body: some View {
        Form {
            if !model.checklist.isReadyToSync {
                Section("Setup") {
                    Text("Finish the remaining steps so Bridge can sync. You can also use the setup window from the menu bar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    setupRow("Sign in to Multica", done: model.checklist.isAuthenticated)
                    setupRow("Workspace selected", done: model.checklist.hasWorkspace)
                    setupRow("Reminders allowed", done: model.checklist.hasRemindersAccess)
                }
            }

            Section("Multica") {
                HStack {
                    Button(model.isConnecting ? "Waiting for browser…" : "Connect Multica") {
                        Task { await model.connectMultica() }
                    }
                    .disabled(model.isConnecting)
                    Button("Test") { Task { await model.testConnection(loadWorkspaceList: true) } }
                    Button("Reload Agents & Projects") {
                        Task { await model.loadCatalog() }
                    }
                    .disabled(model.configuration.workspaceID == nil || model.isLoadingCatalog)
                    Spacer()
                    if model.isLoadingCatalog {
                        ProgressView().controlSize(.small)
                    }
                    Text(model.connectionStatus.components(separatedBy: "\n").first ?? "")
                        .foregroundStyle(model.isAuthenticated ? .green : .secondary)
                }
                Text("After signing in, come back here. Bridge reads the session on its own.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if model.workspaces.isEmpty {
                    HStack {
                        Text("Workspace")
                        Spacer()
                        Button("Reload workspaces") { Task { await model.loadWorkspaces() } }
                    }
                    Text("Choose a workspace from the list — you don’t type an ID.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Picker("Workspace", selection: Binding(
                        get: { model.configuration.workspaceID ?? "" },
                        set: {
                            model.selectWorkspace($0)
                            model.saveConfiguration()
                        }
                    )) {
                        Text("Select…").tag("")
                        ForEach(model.workspaces) { workspace in
                            Text(workspace.displayName).tag(workspace.id)
                        }
                    }
                }

                if let catalogError = model.catalogError {
                    Text(catalogError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
            }

            Section("Agent Requests") {
                Toggle("Send new Reminders to Multica", isOn: $model.configuration.requestDispatchEnabled)
                AppleListField(title: "Apple list", listName: $model.configuration.genericRequestListName, existingLists: model.appleReminderLists)
                AssigneePicker(
                    title: "Who runs these tasks",
                    assignees: model.agents,
                    isLoading: model.isLoadingCatalog,
                    selectedID: model.configuration.defaultAgentID ?? "",
                    onSelect: {
                        model.setDefaultAgent($0)
                        model.saveConfiguration()
                    },
                    onReload: { Task { await model.loadCatalog() } }
                )
                Text("This is who Multica assigns when you create a reminder in “\(model.configuration.genericRequestListName)”. New workspaces default to Mika, the built-in Chief of Staff. A Squad is handled by its leader.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.configuration.defaultAgentID?.isEmpty != false {
                    Text("Pick who should run Agent Requests, or those reminders will stay in Apple Reminders.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                CatalogPicker(
                    title: "Project (optional)",
                    emptyTitle: "No project",
                    items: model.projects.map { ($0.id, $0.name) },
                    isLoading: model.isLoadingCatalog,
                    selectedID: model.configuration.defaultProjectID ?? "",
                    onSelect: {
                        model.setDefaultProject($0)
                        model.saveConfiguration()
                    },
                    onReload: { Task { await model.loadCatalog() } }
                )
                Text("Optional. Used only for reminders in “\(model.configuration.genericRequestListName)”. Project Routes below can send work to a different project.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("When to keep a Main Reminder", selection: $model.configuration.defaultMirrorMode) {
                    ForEach(MirrorMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Text(model.configuration.defaultMirrorMode.helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Project Routes") {
                Text("Connect an Apple Reminders list to a Multica project. Lists inside folders such as Work appear here too. Review / Action Required / Failed stay in the same list.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Reload Apple lists") { Task { await model.refreshAppleReminderLists() } }

                ForEach($model.configuration.projectRoutes) { $route in
                    ProjectRouteEditor(
                        route: $route,
                        projects: model.projects,
                        agents: model.agents,
                        appleLists: model.appleReminderLists,
                        isLoadingCatalog: model.isLoadingCatalog,
                        onReloadCatalog: { Task { await model.loadCatalog() } },
                        onChange: { model.saveConfiguration() },
                        onRemove: { model.removeProjectRoute(id: route.id) }
                    )
                    Divider()
                }
                Button("Add Project Route") { model.addProjectRoute() }
            }

            Section("Notifications") {
                HStack {
                    Button("Allow Reminders") { Task { await model.refreshReminderPermission() } }
                    Button("Create Test Reminder") { Task { await model.createTestReminder() } }
                    Spacer()
                    Text(model.reminderPermissionStatus).foregroundStyle(.secondary)
                }
                Toggle("Notify when a Review / Action Required / Failed Reminder is created", isOn: $model.configuration.reminderAlarmEnabled)
                if model.configuration.reminderAlarmEnabled {
                    Picker("Notify me (Review / Failed)", selection: Binding(
                        get: { model.configuration.reminderAlarmSchedule },
                        set: { schedule in
                            model.configuration.reminderAlarmSchedule = schedule
                            model.configuration.reminderAlarmDelaySeconds = schedule.legacyDelaySeconds
                        }
                    )) {
                        ForEach(HumanAlarmSchedule.allCases, id: \.self) { schedule in
                            Text(schedule.displayName).tag(schedule)
                        }
                    }
                    Text(model.configuration.reminderAlarmSchedule.helpText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker("When I complete a Review Reminder", selection: $model.configuration.reviewCompletionBehavior) {
                    ForEach(ReviewCompletionBehavior.allCases, id: \.self) { behavior in
                        Text(behavior.displayName).tag(behavior)
                    }
                }
                Text("Approve and close treats checking the Review reminder as approval when Multica is still waiting for review. Action Required and Failed stay acknowledge-only. Main Agent-work reminders never get these notifications.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Sync") {
                Stepper(value: pollMinutes, in: 1...60) {
                    Text("Check for new work every \(pollMinutes.wrappedValue) minutes")
                }
                Toggle("Create a reminder when an Agent run fails and does not recover", isOn: $model.configuration.failureRemindersEnabled)
                Toggle("Run at Login", isOn: Binding(
                    get: { model.runAtLogin },
                    set: { model.setRunAtLogin($0) }
                ))
            }

            Section("Diagnostics") {
                if let error = model.lastError {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                }
                Button("Open log folder") { model.openDiagnosticsFolder() }
            }

            DisclosureGroup("Advanced") {
                TextField("Multica CLI path", text: $model.configuration.multicaCLIPath)
                TextField("CLI profile", text: $model.configuration.multicaProfile)
                TextField("App base URL", text: $model.configuration.appBaseURL)
                Stepper(value: $model.configuration.blockedGraceSeconds, in: 0...7200, step: 60) {
                    Text("Wait \(Int(model.configuration.blockedGraceSeconds / 60)) minutes before a blocked issue becomes Action Required")
                }
                Text("Debounce for brief blocked states. If Multica starts a recovery run or leaves blocked on its own, Bridge will not create Action Required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Suppression labels: \(model.configuration.suppressionLabels.sorted().joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Urgent labels: \(model.configuration.urgentLabels.sorted().joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 720, minHeight: 640)
        .onAppear {
            Task {
                await model.refreshAppleReminderLists()
                if model.isAuthenticated {
                    await model.loadWorkspaces()
                    if model.configuration.workspaceID != nil {
                        await model.loadCatalog()
                    }
                }
            }
        }
        .onDisappear { model.saveConfiguration() }
    }

    private var pollMinutes: Binding<Int> {
        Binding(
            get: { max(1, Int((model.configuration.pollIntervalSeconds / 60).rounded())) },
            set: { model.configuration.pollIntervalSeconds = TimeInterval(max(1, $0) * 60) }
        )
    }

    private func setupRow(_ title: String, done: Bool) -> some View {
        HStack {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.green : Color.secondary)
            Text(title)
            Spacer()
        }
    }
}

private struct ProjectRouteEditor: View {
    @Binding var route: ProjectRoute
    let projects: [MulticaProject]
    let agents: [MulticaAgent]
    let appleLists: [String]
    let isLoadingCatalog: Bool
    let onReloadCatalog: () -> Void
    let onChange: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                Button(role: .destructive, action: onRemove) {
                    Label("Remove route", systemImage: "trash")
                }
                .buttonStyle(.plain)
            }

            CatalogPicker(
                title: "Multica Project",
                emptyTitle: "Select project…",
                items: projects.map { ($0.id, $0.name) },
                isLoading: isLoadingCatalog,
                selectedID: route.multicaProjectID ?? "",
                onSelect: { id in
                    route.multicaProjectID = id.isEmpty ? nil : id
                    route.multicaProjectName = projects.first(where: { $0.id == id })?.name
                    onChange()
                },
                onReload: onReloadCatalog
            )

            AppleListField(title: "Apple list", listName: $route.appleListName, existingLists: appleLists)

            AssigneePicker(
                title: "Who runs these tasks",
                assignees: agents,
                isLoading: isLoadingCatalog,
                selectedID: route.defaultAgentID ?? "",
                onSelect: { id in
                    route.defaultAgentID = id.isEmpty ? nil : id
                    route.defaultAgentName = agents.first(where: { $0.id == id })?.name
                    onChange()
                },
                onReload: onReloadCatalog
            )

            Picker("When to keep a Main Reminder", selection: $route.mirrorMode) {
                ForEach(MirrorMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            Text(route.mirrorMode.helpText)
                .font(.caption)
                .foregroundStyle(.secondary)

            if route.appleListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Pick an Apple Reminders list for this project.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if route.defaultAgentID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                Text("Pick who should run reminders in “\(route.appleListName)”. Until then they will not be sent to Multica, unless Agent Requests has an assignee they can fall back to.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}

private struct AssigneePicker: View {
    let title: String
    let assignees: [MulticaAgent]
    let isLoading: Bool
    let selectedID: String
    let onSelect: (String) -> Void
    let onReload: () -> Void

    private var agents: [MulticaAgent] { assignees.filter { $0.kind == .agent } }
    private var squads: [MulticaAgent] { assignees.filter { $0.kind == .squad } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isLoading && assignees.isEmpty {
                HStack {
                    Text(title)
                    Spacer()
                    ProgressView().controlSize(.small)
                    Text("Loading…").foregroundStyle(.secondary)
                }
            } else if assignees.isEmpty {
                HStack {
                    Text(title)
                    Spacer()
                    Button("Reload") { onReload() }
                }
                Text("Couldn’t load Agents and Squads from Multica. Connect, then click Reload.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Picker(title, selection: Binding(
                    get: { selectedID },
                    set: onSelect
                )) {
                    Text("Select…").tag("")
                    ForEach(agents) { item in
                        Text(item.name).tag(item.id)
                    }
                    if !squads.isEmpty {
                        Divider()
                        ForEach(squads) { item in
                            Text(item.menuTitle).tag(item.id)
                        }
                    }
                }
            }
        }
    }
}

private struct CatalogPicker: View {
    let title: String
    let emptyTitle: String
    let items: [(id: String, name: String)]
    let isLoading: Bool
    let selectedID: String
    let onSelect: (String) -> Void
    let onReload: () -> Void

    var body: some View {
        if isLoading && items.isEmpty {
            HStack {
                Text(title)
                Spacer()
                ProgressView().controlSize(.small)
            }
        } else if items.isEmpty {
            HStack {
                Text(title)
                Spacer()
                Button("Reload") { onReload() }
            }
        } else {
            Picker(title, selection: Binding(
                get: { selectedID },
                set: onSelect
            )) {
                Text(emptyTitle).tag("")
                ForEach(items, id: \.id) { item in
                    Text(item.name).tag(item.id)
                }
            }
        }
    }
}

private struct AppleListField: View {
    let title: String
    @Binding var listName: String
    let existingLists: [String]

    private let createTag = "__create_new_apple_list__"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(title, selection: pickerSelection) {
                ForEach(existingLists, id: \.self) { name in
                    Text(name).tag(name)
                }
                Text("Create new list…").tag(createTag)
            }
            if showsCustomNameField {
                TextField("New list name", text: $listName)
                Text("Bridge will create this list in Apple Reminders on the next sync.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if existingLists.isEmpty {
                Text("No Apple Reminders lists loaded yet. Allow Reminders access, then click Reload Apple lists.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var showsCustomNameField: Bool {
        matchedExistingList == nil
    }

    private var matchedExistingList: String? {
        let trimmed = listName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return existingLists.first { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    private var pickerSelection: Binding<String> {
        Binding(
            get: {
                if let matched = matchedExistingList { return matched }
                return createTag
            },
            set: { value in
                if value == createTag {
                    if matchedExistingList != nil { listName = "" }
                } else {
                    listName = value
                }
            }
        )
    }
}

private extension ReviewCompletionBehavior {
    var displayName: String {
        switch self {
        case .closeIssue: return "Approve and close the Multica Issue"
        case .acknowledgeOnly: return "Only clear the reminder"
        }
    }
}
#endif
