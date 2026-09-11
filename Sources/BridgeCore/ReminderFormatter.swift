import Foundation

public struct MulticaDeepLinkBuilder: Sendable {
    public let appBaseURL: String
    public let configuredWorkspaceSlug: String?

    public init(appBaseURL: String, configuredWorkspaceSlug: String?) {
        self.appBaseURL = appBaseURL
        self.configuredWorkspaceSlug = configuredWorkspaceSlug
    }

    public func issueURL(_ issue: IssueSnapshot) -> URL? {
        guard var base = URL(string: appBaseURL) else { return nil }
        let slug = issue.workspaceSlug ?? configuredWorkspaceSlug
        if let slug, !slug.isEmpty {
            base.appendPathComponent(slug)
        }
        base.appendPathComponent("issues")
        base.appendPathComponent(issue.id)
        return base
    }
}

public struct ReminderFormatter: Sendable {
    public let deepLinks: MulticaDeepLinkBuilder

    public init(configuration: BridgeConfiguration) {
        self.deepLinks = MulticaDeepLinkBuilder(appBaseURL: configuration.appBaseURL, configuredWorkspaceSlug: configuration.workspaceSlug)
    }

    public func makeItem(issue: IssueSnapshot, decision: AttentionDecision, reviewGeneration: Int) -> HumanAttentionItem {
        let prefix: String
        switch decision.reason {
        case .blockedRequiresHuman: prefix = "Unblock"
        case .failedRequiresHuman: prefix = "Check failed Agent task"
        default: prefix = "Review"
        }

        let reasonLine: String
        switch decision.reason {
        case .reviewRequired: reasonLine = "Agent 已交付结果，等待人工 Review。"
        case .blockedRequiresHuman: reasonLine = "任务仍被阻塞，需要人工介入。"
        case .failedRequiresHuman: reasonLine = "最近一次 Agent Run 失败，当前没有可见的自动恢复。"
        case .explicitAlways: reasonLine = "该任务被显式标记为需要提醒。"
        default: reasonLine = "该任务需要人工处理。"
        }

        var lines: [String] = []
        let agent = issue.assigneeName ?? issue.latestRun?.agentName
        if let agent { lines.append("\(issue.key) · \(agent)") }
        else { lines.append(issue.key) }
        lines.append(reasonLine)
        if let summary = compact(issue.summary, max: 420), !summary.isEmpty { lines.append("") ; lines.append(summary) }
        if let run = issue.latestRun { lines.append("") ; lines.append("Latest run: \(run.status.rawValue)") }
        if reviewGeneration > 1 { lines.append("Review cycle: #\(reviewGeneration)") }

        return HumanAttentionItem(
            issueID: issue.id,
            issueKey: issue.key,
            reviewGeneration: reviewGeneration,
            title: "\(prefix): \(issue.title)",
            notes: lines.joined(separator: "\n"),
            url: deepLinks.issueURL(issue),
            priority: decision.severity,
            dueDate: issue.dueDate
        )
    }

    public func payloadHash(_ item: HumanAttentionItem) -> String {
        StableHash.hex([item.title, item.notes, item.url?.absoluteString ?? "", item.priority.rawValue, item.dueDate?.timeIntervalSince1970.description ?? ""].joined(separator: "\u{1f}"))
    }

    private func compact(_ raw: String?, max: Int) -> String? {
        guard let raw else { return nil }
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > max else { return normalized }
        return String(normalized.prefix(max - 1)) + "…"
    }
}
