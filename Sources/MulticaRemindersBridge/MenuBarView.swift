#if os(macOS)
import BridgeCore
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: BridgeAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Multica Reminders Bridge").font(.headline)
            Divider()
            if model.checklist.isReadyToSync {
                readyMenu
            } else {
                setupMenu
            }
            Divider()
            if model.checklist.isReadyToSync {
                Button(model.isSyncing ? "Syncing…" : "Sync now") {
                    Task { await model.syncNow() }
                }.disabled(model.isSyncing)
                Button("Open Multica Reviews") { model.openReviewBoard() }
            }
            Button("Settings…") { model.openSettingsWindow() }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .padding(10)
        .frame(width: 360)
    }

    private var setupMenu: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Finish setup to start syncing", systemImage: "sparkles")
                .font(.subheadline.weight(.medium))
            checklistRow("Sign in to Multica", done: model.checklist.isAuthenticated)
            checklistRow("Choose a workspace", done: model.checklist.hasWorkspace)
            checklistRow("Allow Reminders", done: model.checklist.hasRemindersAccess)
            Button("Continue setup…") {
                model.openOnboardingWindow()
            }
        }
    }

    private var readyMenu: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                model.connectionStatus.components(separatedBy: "\n").first ?? model.connectionStatus,
                systemImage: "checkmark.circle.fill"
            )
            if let workspace = model.configuration.workspaceSlug ?? model.configuration.workspaceID {
                Text("Workspace: \(workspace)").font(.caption).foregroundStyle(.secondary)
            }
            if let summary = model.lastSyncSummary {
                Text("Last sync: \(summary.finishedAt.formatted(date: .omitted, time: .shortened)) · \(summary.createdOrUpdated) updated · \(summary.reviewApprovals) approved · \(summary.resolved) resolved")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = model.lastError {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(3)
            }
        }
    }

    private func checklistRow(_ title: String, done: Bool, optional: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.green : Color.secondary)
            Text(optional ? "\(title) — optional" : title)
                .foregroundStyle(done ? Color.secondary : Color.primary)
        }
        .font(.caption)
    }
}
#endif
