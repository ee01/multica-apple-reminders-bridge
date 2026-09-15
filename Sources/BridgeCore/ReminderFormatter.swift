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
        let pathID = issue.key.trimmingCharacters(in: .whitespacesAndNewlines)
        base.appendPathComponent(pathID.isEmpty ? issue.id : pathID)
        return base
    }
}

public struct ReminderFormatter: Sendable {
    public let deepLinks: MulticaDeepLinkBuilder
    private let alarmEnabled: Bool
    private let alarmSchedule: HumanAlarmSchedule

    public init(configuration: BridgeConfiguration) {
        self.deepLinks = MulticaDeepLinkBuilder(appBaseURL: configuration.appBaseURL, configuredWorkspaceSlug: configuration.workspaceSlug)
        self.alarmEnabled = configuration.reminderAlarmEnabled
        self.alarmSchedule = configuration.reminderAlarmSchedule
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
        case .reviewRequired: reasonLine = "Agent 已交付，等待你 Review。"
        case .blockedRequiresHuman: reasonLine = "任务被 Blocked，需要你处理。"
        case .failedRequiresHuman: reasonLine = "最近一次 Agent Run 失败，且没有新的重试。"
        case .explicitAlways: reasonLine = "该任务被标记为需要你关注。"
        default: reasonLine = "该任务需要你处理。"
        }

        var lines: [String] = [issue.key, reasonLine]

        let asks = issue.recentMemberAsks.map { compact($0, max: 240) }.compactMap { $0 }.filter { !$0.isEmpty }
        if !asks.isEmpty {
            lines.append("")
            lines.append("Latest from you:")
            lines.append(contentsOf: asks)
        } else if let context = compact(issue.issueDescription ?? issue.summary, max: 280), !context.isEmpty {
            lines.append("")
            lines.append("What this is:")
            lines.append(context)
        }

        if let project = issue.projectName { lines.append(""); lines.append("Project: \(project)") }
        if let agent = issue.assigneeName ?? issue.latestRun?.agentName { lines.append("Agent: \(agent)") }
        if generation > 1 { lines.append("Review round: #\(generation)") }
        if decision.reason == .failedRequiresHuman, let run = issue.latestRun {
            if let reason = run.failureReasonCode, !reason.isEmpty { lines.append("Failure: \(reason)") }
            if let error = compact(run.errorMessage, max: 220), !error.isEmpty { lines.append("Error: \(error)") }
        }

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
            alarmDate: alarmEnabled ? alarmSchedule.alarmDate(from: now) : nil
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
        var normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        normalized = normalized.replacingOccurrences(of: #"(?m)^#{1,6}\s+"#, with: "", options: .regularExpression)
        while normalized.contains("\n\n\n") {
            normalized = normalized.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        guard normalized.count > max else { return normalized }
        return String(normalized.prefix(max - 1)) + "…"
    }
}
