#if os(macOS)
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

            Section("Apple Reminders") {
                TextField("List name", text: $model.configuration.reminderListName)
                HStack {
                    Button("Grant / Check Permission") { Task { await model.refreshReminderPermission() } }
                    Button("Create Test Reminder") { Task { await model.createTestReminder() } }
                    Spacer()
                    Text(model.reminderPermissionStatus).foregroundStyle(.secondary)
                }
                Toggle("Notify when a new human-review Reminder is created", isOn: $model.configuration.reminderAlarmEnabled)
                if model.configuration.reminderAlarmEnabled {
                    Stepper(value: $model.configuration.reminderAlarmDelaySeconds, in: 0...900, step: 30) {
                        Text("Notification alarm after \(Int(model.configuration.reminderAlarmDelaySeconds)) seconds")
                    }
                }
            }

            Section("Sync") {
                Stepper(value: $model.configuration.pollIntervalSeconds, in: 30...3600, step: 30) {
                    Text("Poll every \(Int(model.configuration.pollIntervalSeconds)) seconds")
                }
                Stepper(value: $model.configuration.blockedGraceSeconds, in: 0...7200, step: 60) {
                    Text("Blocked grace \(Int(model.configuration.blockedGraceSeconds / 60)) minutes")
                }
                Toggle("Create reminders for unrecovered failed runs", isOn: $model.configuration.failureRemindersEnabled)
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
        .frame(width: 620, height: 620)
    }
}
#endif
