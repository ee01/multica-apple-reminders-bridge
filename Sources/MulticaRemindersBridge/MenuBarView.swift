#if os(macOS)
import BridgeCore
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: BridgeAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Multica Reminders Bridge").font(.headline)
            Divider()
            Label(model.connectionStatus.components(separatedBy: "\n").first ?? model.connectionStatus,
                  systemImage: model.connectionStatus.hasPrefix("Connected") ? "checkmark.circle.fill" : "exclamationmark.circle")
            if let workspace = model.configuration.workspaceSlug ?? model.configuration.workspaceID {
                Text("Workspace: \(workspace)").font(.caption).foregroundStyle(.secondary)
            }
            if let summary = model.lastSyncSummary {
                Text("Last sync: \(summary.finishedAt.formatted(date: .omitted, time: .shortened)) · \(summary.createdOrUpdated) updated · \(summary.resolved) resolved")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = model.lastError {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(3)
            }
            Divider()
            Button(model.isSyncing ? "Syncing…" : "Sync now") {
                Task { await model.syncNow() }
            }.disabled(model.isSyncing)
            Button("Open Multica Reviews") { model.openReviewBoard() }
            SettingsLink { Text("Settings…") }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .padding(10)
        .frame(width: 340)
    }
}
#endif
