import Foundation

public final class SyncEngine: @unchecked Sendable {
    private let source: any MulticaSource
    private let sink: any ReminderSink
    private let persistence: any BridgePersistence
    private let policy: AttentionPolicy
    private let formatter: ReminderFormatter
    private let configuration: BridgeConfiguration

    public init(source: any MulticaSource, sink: any ReminderSink, persistence: any BridgePersistence, configuration: BridgeConfiguration) {
        self.source = source
        self.sink = sink
        self.persistence = persistence
        self.configuration = configuration
        self.policy = AttentionPolicy(configuration: configuration)
        self.formatter = ReminderFormatter(configuration: configuration)
    }

    public func sync(now: Date = Date()) async throws -> SyncSummary {
        var summary = SyncSummary()
        var issues = try await source.fetchIssues()
        summary.fetchedIssues = issues.count

        // If Multica's list omits closed issues, explicitly refresh anything that still
        // owns an active Reminder projection before reconciling.
        let active = try persistence.activeProjections()
        let fetchedIDs = Set(issues.map(\.id))
        for projection in active where !fetchedIDs.contains(projection.issueID) {
            do {
                let issue = try await source.fetchIssue(idOrKey: projection.issueKey)
                issues.append(issue)
            } catch {
                // A transient Cloud/list/get failure must never be interpreted as "done".
                summary.errors.append("refresh \(projection.issueKey): \(error)")
            }
        }

        issues = deduplicate(issues)
        issues = await hydrateLatestRuns(issues, summary: &summary)

        for issue in issues {
            do {
                try await reconcile(issue: issue, now: now, summary: &summary)
            } catch {
                summary.errors.append("\(issue.key): \(error)")
            }
        }

        summary.finishedAt = Date()
        try persistence.setMeta(key: "last_sync_finished_at", value: String(summary.finishedAt.timeIntervalSince1970))
        try persistence.setMeta(key: "last_sync_error_count", value: String(summary.errors.count))
        return summary
    }

    private func hydrateLatestRuns(_ input: [IssueSnapshot], summary: inout SyncSummary) async -> [IssueSnapshot] {
        let candidates = input.enumerated().filter { _, issue in
            switch issue.statusCategory {
            case .inReview, .blocked: return issue.latestRun == nil
            case .todo: return configuration.failureRemindersEnabled && issue.latestRun == nil
            default: return false
            }
        }.sorted { lhs, rhs in
            (lhs.element.updatedAt ?? .distantPast) > (rhs.element.updatedAt ?? .distantPast)
        }.prefix(max(0, configuration.maxRunHydrationPerSync))

        var output = input
        for (index, issue) in candidates {
            do {
                let runs = try await source.fetchRuns(issueIDOrKey: issue.key)
                if let latest = runs.first { output[index].latestRun = latest }
            } catch {
                summary.errors.append("runs \(issue.key): \(error)")
            }
        }
        return output
    }

    private func reconcile(issue: IssueSnapshot, now: Date, summary: inout SyncSummary) async throws {
        let previous = try persistence.observation(issueID: issue.id)
        let generation = ReviewCycleDetector.nextGeneration(previous: previous, current: issue)
        let firstBlockedAt = ReviewCycleDetector.firstBlockedAt(previous: previous, current: issue, now: now)

        let workingObservation = IssueObservation(
            issueID: issue.id,
            issueKey: issue.key,
            statusName: issue.statusName,
            statusCategory: issue.statusCategory,
            reviewGeneration: generation,
            latestRunID: issue.latestRun?.id,
            latestRunStatus: issue.latestRun?.status,
            payloadHash: previous?.payloadHash,
            observedUpdatedAt: issue.updatedAt,
            firstBlockedAt: firstBlockedAt,
            updatedAt: now
        )
        let decision = policy.decide(issue: issue, observation: workingObservation, now: now)

        switch decision.action {
        case .resolveReminder:
            try await resolveActiveProjections(issueID: issue.id, summary: &summary, now: now)
            try persistence.upsertObservation(workingObservation)

        case .none:
            // If human attention is no longer required (e.g. review -> rework, blocked -> retry),
            // retire stale active projections. A later review transition increments generation.
            try await resolveActiveProjections(issueID: issue.id, summary: &summary, now: now)
            try persistence.upsertObservation(workingObservation)

        case .createOrUpdateReminder:
            let item = formatter.makeItem(issue: issue, decision: decision, reviewGeneration: generation)
            let payloadHash = formatter.payloadHash(item)
            var observation = workingObservation
            observation.payloadHash = payloadHash

            var projection = try persistence.projection(issueID: issue.id, reviewGeneration: generation)
            if var existing = projection {
                if existing.userAcknowledged || existing.state == .acknowledged || existing.state == .dismissed {
                    try persistence.upsertObservation(observation)
                    return
                }

                if let receipt = existing.receipt {
                    switch try await sink.state(of: receipt, issueKey: existing.issueKey, reviewGeneration: existing.reviewGeneration) {
                    case .completed:
                        existing.userAcknowledged = true
                        existing.state = .acknowledged
                        existing.updatedAt = now
                        try persistence.upsertProjection(existing)
                        try persistence.upsertObservation(observation)
                        summary.acknowledged += 1
                        return
                    case .missing:
                        existing.userAcknowledged = true
                        existing.state = .dismissed
                        existing.updatedAt = now
                        try persistence.upsertProjection(existing)
                        try persistence.upsertObservation(observation)
                        summary.acknowledged += 1
                        return
                    case .pending:
                        break
                    }
                }

                if existing.payloadHash == payloadHash, existing.state == .active {
                    try persistence.upsertObservation(observation)
                    return
                }
            }

            do {
                let receipt = try await sink.upsert(item, existing: projection?.receipt)
                if projection == nil {
                    projection = ReminderProjection(issueID: issue.id, issueKey: issue.key, reviewGeneration: generation)
                }
                projection?.receipt = receipt
                projection?.state = .active
                projection?.userAcknowledged = false
                projection?.payloadHash = payloadHash
                projection?.updatedAt = now
                if let projection { try persistence.upsertProjection(projection) }
                try persistence.upsertObservation(observation)
                summary.createdOrUpdated += 1
            } catch {
                if projection == nil {
                    projection = ReminderProjection(issueID: issue.id, issueKey: issue.key, reviewGeneration: generation)
                }
                projection?.state = .pendingRetry
                projection?.payloadHash = payloadHash
                projection?.updatedAt = now
                if let projection { try persistence.upsertProjection(projection) }
                try persistence.upsertObservation(observation)
                throw error
            }
        }
    }

    private func resolveActiveProjections(issueID: String, summary: inout SyncSummary, now: Date) async throws {
        let projections = try persistence.activeProjections(issueID: issueID)
        for var projection in projections {
            do {
                if let receipt = projection.receipt { try await sink.resolve(receipt, issueKey: projection.issueKey, reviewGeneration: projection.reviewGeneration) }
                projection.state = .resolved
                projection.updatedAt = now
                try persistence.upsertProjection(projection)
                summary.resolved += 1
            } catch {
                projection.state = .pendingRetry
                projection.updatedAt = now
                try persistence.upsertProjection(projection)
                throw error
            }
        }
    }

    private func deduplicate(_ values: [IssueSnapshot]) -> [IssueSnapshot] {
        var byID: [String: IssueSnapshot] = [:]
        for value in values { byID[value.id] = value }
        return Array(byID.values)
    }
}
