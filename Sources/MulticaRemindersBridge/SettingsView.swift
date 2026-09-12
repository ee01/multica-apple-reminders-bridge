#if os(macOS)
import BridgeCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: BridgeAppModel

    var body: some View {
        Form {
            Section("Multica Cloud") {
                TextField("CLI path", text: $model.configuration.multicaCLIPath)
                TextField("CLI profile", text: $model.configuration.multicaProfile)
                HStack {
                    Button("Connect Multica") { Task { await model.connectMultica() } }
                    Button("Test") { Task { await model.testConnection(loadWorkspaceList: true) } }
                    Button("Refresh Projects / Agents") { Task { await model.loadCatalog() } }
                        .disabled(model.configuration.workspaceID == nil)
                    Spacer()
                    Text(model.connectionStatus.components(separatedBy: "\n").first ?? "")
                        .foregroundStyle(.secondary)
                }
                if !model.workspaces.isEmpty {
                    Picker("Workspace", selection: Binding(
                        get: { model.configuration.workspaceID ?? "" },
                        set: { model.selectWorkspace($0) }
                    )) {
                        Text("Select…").tag("")
                        ForEach(model.workspaces) { workspace in
                            Text(workspace.displayName).tag(workspace.id)
                        }
                    }
                } else {
                    TextField("Workspace ID (optional)", text: Binding(
                        get: { model.configuration.workspaceID ?? "" },
                        set: { model.configuration.workspaceID = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("Workspace slug (for deep links)", text: Binding(
                        get: { model.configuration.workspaceSlug ?? "" },
                        set: { model.configuration.workspaceSlug = $0.isEmpty ? nil : $0 }
                    ))
                }
                TextField("App base URL", text: $model.configuration.appBaseURL)
            }

            Section("Apple → Multica Requests") {
                Toggle("Dispatch new Reminders to Multica", isOn: $model.configuration.requestDispatchEnabled)
                TextField("Generic request list", text: $model.configuration.genericRequestListName)
                Picker("Default mirror mode", selection: $model.configuration.defaultMirrorMode) {
                    ForEach(MirrorMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Text("apple_origin_only is the default: Apple-created Agent work keeps a Main Reminder, while Multica-created work only appears when human attention is required unless a project route overrides it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !model.projects.isEmpty {
                    Picker("Fallback Multica project", selection: Binding(
                        get: { model.configuration.defaultProjectID ?? "" },
                        set: { model.setDefaultProject($0) }
                    )) {
                        Text("None").tag("")
                        ForEach(model.projects) { project in Text(project.name).tag(project.id) }
                    }
                } else {
                    TextField("Fallback project ID", text: Binding(
                        get: { model.configuration.defaultProjectID ?? "" },
                        set: { model.configuration.defaultProjectID = $0.isEmpty ? nil : $0 }
                    ))
                }

                if !model.agents.isEmpty {
                    Picker("Fallback Agent", selection: Binding(
                        get: { model.configuration.defaultAgentID ?? "" },
                        set: { model.setDefaultAgent($0) }
                    )) {
                        Text("Select Agent…").tag("")
                        ForEach(model.agents) { agent in Text(agent.name).tag(agent.id) }
                    }
                } else {
                    TextField("Fallback Agent ID", text: Binding(
                        get: { model.configuration.defaultAgentID ?? "" },
                        set: { model.configuration.defaultAgentID = $0.isEmpty ? nil : $0 }
                    ))
                }
            }

            Section("Project Routes") {
                Text("Pin frequently used Apple Reminder lists to Multica Projects. Main work and its Review/Unblock/Failure sibling stay in the same project list.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach($model.configuration.projectRoutes) { $route in
                    ProjectRouteEditor(
                        route: $route,
                        projects: model.projects,
                        agents: model.agents,
                        onRemove: { model.removeProjectRoute(id: route.id) }
                    )
                    Divider()
                }
                Button("Add Project Route") { model.addProjectRoute() }
            }

            Section("Human Attention") {
                HStack {
                    Button("Grant / Check Reminders Permission") { Task { await model.refreshReminderPermission() } }
                    Button("Create Test Reminder") { Task { await model.createTestReminder() } }
                    Spacer()
                    Text(model.reminderPermissionStatus).foregroundStyle(.secondary)
                }
                Toggle("Notify when a Review / Unblock / Failure Reminder is created", isOn: $model.configuration.reminderAlarmEnabled)
                if model.configuration.reminderAlarmEnabled {
                    Stepper(value: $model.configuration.reminderAlarmDelaySeconds, in: 0...900, step: 30) {
                        Text("Human-action alarm after \(Int(model.configuration.reminderAlarmDelaySeconds)) seconds")
                    }
                }
                Text("Main Agent-work Reminders never receive Bridge-managed notification alarms. Only Human Action siblings do.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Sync") {
                Stepper(value: $model.configuration.pollIntervalSeconds, in: 30...3600, step: 30) {
                    Text("Poll every \(Int(model.configuration.pollIntervalSeconds)) seconds")
                }
                Stepper(value: $model.configuration.blockedGraceSeconds, in: 0...7200, step: 60) {
                    Text("Blocked grace \(Int(model.configuration.blockedGraceSeconds / 60)) minutes")
                }
                Toggle("Create human-action reminders for unrecovered failed runs", isOn: $model.configuration.failureRemindersEnabled)
                Toggle("Run at Login", isOn: Binding(
                    get: { model.runAtLogin },
                    set: { model.setRunAtLogin($0) }
                ))
            }

            Section("Overrides") {
                Text("Suppression labels: \(model.configuration.suppressionLabels.sorted().joined(separator: ", "))")
                    .font(.caption)
                Text("Urgent labels: \(model.configuration.urgentLabels.sorted().joined(separator: ", "))")
                    .font(.caption)
            }

            if let error = model.lastError {
                Section("Diagnostics") {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                    Button("Open Diagnostics Folder") { model.openDiagnosticsFolder() }
                }
            }

            HStack {
                Spacer()
                Button("Save") {
                    model.saveConfiguration()
                    model.stop()
                    model.start()
                }.keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 760, height: 820)
    }
}

private struct ProjectRouteEditor: View {
    @Binding var route: ProjectRoute
    let projects: [MulticaProject]
    let agents: [MulticaAgent]
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Apple list", text: $route.appleListName)
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            if !projects.isEmpty {
                Picker("Multica Project", selection: Binding(
                    get: { route.multicaProjectID ?? "" },
                    set: { id in
                        route.multicaProjectID = id.isEmpty ? nil : id
                        route.multicaProjectName = projects.first(where: { $0.id == id })?.name
                    }
                )) {
                    Text("None").tag("")
                    ForEach(projects) { project in Text(project.name).tag(project.id) }
                }
            } else {
                TextField("Multica Project ID", text: Binding(
                    get: { route.multicaProjectID ?? "" },
                    set: { route.multicaProjectID = $0.isEmpty ? nil : $0 }
                ))
            }

            if !agents.isEmpty {
                Picker("Default Agent", selection: Binding(
                    get: { route.defaultAgentID ?? "" },
                    set: { id in
                        route.defaultAgentID = id.isEmpty ? nil : id
                        route.defaultAgentName = agents.first(where: { $0.id == id })?.name
                    }
                )) {
                    Text("Select Agent…").tag("")
                    ForEach(agents) { agent in Text(agent.name).tag(agent.id) }
                }
            } else {
                TextField("Default Agent ID", text: Binding(
                    get: { route.defaultAgentID ?? "" },
                    set: { route.defaultAgentID = $0.isEmpty ? nil : $0 }
                ))
            }

            Picker("Mirror mode", selection: $route.mirrorMode) {
                ForEach(MirrorMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
        }
    }
}

private extension MirrorMode {
    var displayName: String {
        switch self {
        case .appleOriginOnly: return "Apple origin only (default)"
        case .allActive: return "All active Multica issues"
        case .attentionOnly: return "Human attention only"
        }
    }
}
#endif
