import Foundation

public struct AttentionPolicy: Sendable {
    public let configuration: BridgeConfiguration

    public init(configuration: BridgeConfiguration) { self.configuration = configuration }

    public func decide(issue: IssueSnapshot, observation: IssueObservation?, now: Date = Date()) -> AttentionDecision {
        let labels = Set(issue.labels.map { $0.lowercased() })
        if !labels.isDisjoint(with: configuration.suppressionLabels.map { $0.lowercased() }) {
            return AttentionDecision(action: .none, reason: .suppressed)
        }
        if issue.statusCategory.isTerminal {
            return AttentionDecision(action: .resolveReminder, reason: .terminal)
        }

        // A real active run means the agent owns the current turn, even if the Issue's
        // status is still stale `in_review` after a comment-triggered rework run.
        if issue.latestRun?.status.isActive == true {
            return AttentionDecision(action: .none, reason: .activeOrNoAction)
        }

        let severity = deriveSeverity(issue: issue)
        if !labels.isDisjoint(with: configuration.alwaysLabels.map { $0.lowercased() }) {
            return AttentionDecision(action: .createOrUpdateReminder, reason: .explicitAlways, severity: severity)
        }
        if issue.statusCategory == .inReview {
            return AttentionDecision(action: .createOrUpdateReminder, reason: .reviewRequired, severity: severity)
        }
        if issue.statusCategory == .blocked {
            let firstBlocked = observation?.firstBlockedAt ?? now
            if now.timeIntervalSince(firstBlocked) >= configuration.blockedGraceSeconds {
                return AttentionDecision(action: .createOrUpdateReminder, reason: .blockedRequiresHuman, severity: severity)
            }
            return AttentionDecision(action: .none, reason: .activeOrNoAction)
        }
        if configuration.failureRemindersEnabled, issue.latestRun?.status == .failed {
            return AttentionDecision(action: .createOrUpdateReminder, reason: .failedRequiresHuman, severity: severity)
        }
        return AttentionDecision(action: .none, reason: .activeOrNoAction)
    }

    private func deriveSeverity(issue: IssueSnapshot) -> AttentionSeverity {
        let labels = Set(issue.labels.map { $0.lowercased() })
        if !labels.isDisjoint(with: configuration.urgentLabels.map { $0.lowercased() }) || issue.priority == .urgent { return .urgent }
        if issue.priority == .high { return .high }
        return .normal
    }
}

public enum ReviewCycleDetector {
    public static func nextGeneration(previous: IssueObservation?, current: IssueSnapshot) -> Int {
        let existing = previous?.reviewGeneration ?? 0
        guard current.statusCategory == .inReview else { return existing }
        guard let previous else { return existing + 1 }
        if previous.statusCategory != .inReview { return existing + 1 }
        // A comment can start a rework run without changing Issue status. Once that run
        // finishes and the Issue is still in_review, it is a fresh review cycle.
        if previous.latestRunStatus?.isActive == true,
           current.latestRun?.status.isActive != true {
            return existing + 1
        }
        return max(existing, 1)
    }

    public static func firstBlockedAt(previous: IssueObservation?, current: IssueSnapshot, now: Date) -> Date? {
        guard current.statusCategory == .blocked else { return nil }
        if previous?.statusCategory == .blocked { return previous?.firstBlockedAt ?? now }
        return now
    }
}
