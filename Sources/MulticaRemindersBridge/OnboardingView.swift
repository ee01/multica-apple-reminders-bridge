#if os(macOS)
import BridgeCore
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: BridgeAppModel

    private var step: SetupStep { model.checklist.nextStep }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            progress
            stepBody
            Spacer(minLength: 8)
            footer
        }
        .padding(28)
        .frame(width: 540, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Set up Reminders Bridge")
                .font(.title2.weight(.semibold))
            Text("A few steps so Apple Reminders and Multica can talk to each other.")
                .foregroundStyle(.secondary)
        }
    }

    private var progress: some View {
        HStack(spacing: 8) {
            ForEach(Array(SetupStep.allCases.dropLast().enumerated()), id: \.offset) { index, value in
                Capsule()
                    .fill(value.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.2))
                    .frame(height: 4)
                    .accessibilityLabel("Step \(index + 1)")
            }
        }
    }

    @ViewBuilder
    private var stepBody: some View {
        switch step {
        case .connect:
            stepCard(
                title: "Sign in to Multica",
                body: "A browser window will open. After you finish OAuth, come back here — Bridge reads the session automatically and should switch to Connected without clicking Test."
            ) {
                Button(model.isConnecting ? "Waiting for browser…" : "Connect Multica") {
                    Task { await model.connectMultica() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isConnecting)
                if model.isConnecting {
                    Text("Complete sign-in in the browser, then return to this window.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .workspace:
            stepCard(
                title: "Choose a workspace",
                body: "This is the Multica workspace Bridge will read and write. You don’t type an ID — pick it from the list."
            ) {
                if model.workspaces.isEmpty {
                    Button("Reload workspaces") {
                        Task { await model.loadWorkspaces() }
                    }
                } else {
                    Picker("Workspace", selection: Binding(
                        get: { model.configuration.workspaceID ?? "" },
                        set: { model.selectWorkspace($0) }
                    )) {
                        Text("Select…").tag("")
                        ForEach(model.workspaces) { workspace in
                            Text(workspace.displayName).tag(workspace.id)
                        }
                    }
                    .labelsHidden()
                }
            }
        case .reminders:
            stepCard(
                title: "Allow Apple Reminders",
                body: "Bridge creates and updates reminders in your lists. macOS will ask for access once."
            ) {
                HStack {
                    Button("Allow Reminders") {
                        Task { await model.refreshReminderPermission(prompt: true) }
                    }
                    .keyboardShortcut(.defaultAction)
                    Text(model.reminderPermissionStatus)
                        .foregroundStyle(.secondary)
                }
            }
        case .done:
            stepCard(
                title: "You’re ready",
                body: doneBody
            ) {
                Button("Create a test Reminder") {
                    Task { await model.createTestReminder() }
                }
            }
        }
    }

    private var doneBody: String {
        if let name = model.configuration.defaultAgentName, !name.isEmpty {
            return "New reminders in Agent Requests are assigned to \(name). Change this later in Settings if you want a different Agent or Squad."
        }
        return "Create a Reminder in Agent Requests or a Project Route list to send work to Multica. When an agent needs you, Bridge adds a Review or Action Required reminder."
    }

    private var footer: some View {
        HStack {
            Spacer()
            if step == .done {
                Button("Open Settings") {
                    model.openSettingsWindow()
                    model.closeOnboardingWindow()
                }
                Button("Done") { model.closeOnboardingWindow() }
                    .keyboardShortcut(.defaultAction)
            } else if let error = model.lastError, model.isConnecting == false, step == .connect {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }

    private func stepCard<Content: View>(title: String, body: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title3.weight(.semibold))
            Text(body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
    }
}
#endif
