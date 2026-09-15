import Foundation

public struct MainReminderFormatter: Sendable {
    private let deepLinks: MulticaDeepLinkBuilder

    public init(configuration: BridgeConfiguration) {
        self.deepLinks = MulticaDeepLinkBuilder(appBaseURL: configuration.appBaseURL, configuredWorkspaceSlug: configuration.workspaceSlug)
    }

    public func makeItem(issue: IssueSnapshot, listName: String) -> ReminderItem {
        var lines: [String] = ["Multica: \(issue.key)"]
        if let project = issue.projectName { lines.append("Project: \(project)") }
        if let assignee = issue.assigneeName ?? issue.latestRun?.agentName { lines.append("Agent: \(assignee)") }
        lines.append("Status: \(issue.statusName)")
        if let due = issue.dueDate { lines.append("Multica due: \(ISO8601DateFormatter().string(from: due))") }
        if let summary = compact(issue.summary ?? issue.issueDescription, max: 360), !summary.isEmpty {
            lines.append("")
            lines.append(summary)
        }
        return ReminderItem(
            issueID: issue.id,
            issueKey: issue.key,
            kind: .main,
            generation: 0,
            listName: listName,
            title: issue.title,
            notes: lines.joined(separator: "\n"),
            url: deepLinks.issueURL(issue),
            priority: issue.priority == .urgent ? .urgent : (issue.priority == .high ? .high : .normal),
            // Main Agent work is intentionally not scheduled as a human alert.
            dueDate: nil,
            alarmDate: nil
        )
    }

    public func payloadHash(_ item: ReminderItem) -> String {
        StableHash.hex([item.listName, item.title, item.notes, item.url?.absoluteString ?? "", item.priority.rawValue].joined(separator: "\u{1f}"))
    }

    private func compact(_ raw: String?, max: Int) -> String? {
        guard let raw else { return nil }
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > max else { return normalized }
        return String(normalized.prefix(max - 1)) + "…"
    }
}
