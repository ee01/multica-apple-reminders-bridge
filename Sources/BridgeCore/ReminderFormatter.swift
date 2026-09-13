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
        if let slug, !slug.isEmpty { base.appendPathComponent(slug) }
        base.appendPathComponent("issues")
        base.appendPathComponent(issue.id)
        return base
    }
}

public struct ReminderFormatter: Sendable {
    public let deepLinks: MulticaDeepLinkBuilder
    private let alarmEnabled: Bool
    private let alarmDelay: TimeInterval

    public init(configuration: BridgeConfiguration) {
        self.deepLinks = MulticaDeepLinkBuilder(appBaseURL: configuration.appBaseURL, configuredWorkspaceSlug: configuration.workspaceSlug)
        self.alarmEnabled = configuration.reminderAlarmEnabled
        self.alarmDelay = max(0, configuration.reminderAlarmDelaySeconds)
    }

    public func makeItem(issue: IssueSnapshot, decision: AttentionDecision, generation: Int, listName: String, now: Date) -> ReminderItem {
        let prefix: String
        let actionKind: HumanActionKind
        switch decision.reason {
        case .blockedRequiresHuman: prefix = "Action Required"; actionKind = .actionRequired
        case .failedRequiresHuman: prefix = "Failed"; actionKind = .failed
        case .explicitAlways: prefix = "Action Required"; actionKind = .actionRequired
        default: prefix = "Review"; actionKind = .review
        }

        let reasonLine: String
        switch decision.reason {
        case .reviewRequired: reasonLine = "Agent 已交付结果，等待人工 Review。"
        case .blockedRequiresHuman: reasonLine = "任务处于 Blocked，自动化不会自行继续，需要人工介入。"
        case .failedRequiresHuman: reasonLine = "最近一次 Agent Run 已失败，且当前没有新的活动重试。"
        case .explicitAlways: reasonLine = "该任务被显式标记为需要人工关注。"
        default: reasonLine = "该任务需要人工处理。"
        }

        var lines: [String] = [issue.key, reasonLine]
        if let project = issue.projectName { lines.insert("Project: \(project)", at: 1) }
        if let agent = issue.assigneeName ?? issue.latestRun?.agentName { lines.insert("Agent: \(agent)", at: min(2, lines.count)) }
        if let summary = compact(issue.summary, max: 420), !summary.isEmpty { lines.append(""); lines.append(summary) }
        if let run = issue.latestRun {
            lines.append("")
            lines.append("Latest run: \(run.status.rawValue)")
            if let reason = run.failureReasonCode, !reason.isEmpty { lines.append("Failure reason: \(reason)") }
            if let error = compact(run.errorMessage, max: 300), !error.isEmpty { lines.append("Error: \(error)") }
        }
        if generation > 1 { lines.append("Human action cycle: #\(generation)") }

        _ = actionKind // Kept here to make the title/reason mapping explicit; projection stores it separately.
        return ReminderItem(
            issueID: issue.id,
            issueKey: issue.key,
            kind: .humanAction,
            generation: generation,
            listName: listName,
            title: "\(prefix): \(issue.title)",
            notes: lines.joined(separator: "\n"),
            url: deepLinks.issueURL(issue),
            priority: decision.severity,
            dueDate: nil,
            alarmDate: alarmEnabled ? now.addingTimeInterval(alarmDelay) : nil
        )
    }

    public func actionKind(for decision: AttentionDecision) -> HumanActionKind {
        switch decision.reason {
        case .blockedRequiresHuman, .explicitAlways: return .actionRequired
        case .failedRequiresHuman: return .failed
        default: return .review
        }
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
