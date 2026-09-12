import Foundation

public final class SyncEngine: @unchecked Sendable {
    private let source: any MulticaSource
    private let sink: any ReminderSink
    private let persistence: any BridgePersistence
    private let attentionPolicy: AttentionPolicy
    private let projectionPolicy: ProjectProjectionPolicy
    private let requestRouter: AgentRequestRouter
    private let attentionFormatter: ReminderFormatter
    private let mainFormatter: MainReminderFormatter
    private let configuration: BridgeConfiguration

    public init(source: any MulticaSource, sink: any ReminderSink, persistence: any BridgePersistence, configuration: BridgeConfiguration) {
        self.source = source
        self.sink = sink
        self.persistence = persistence
        self.configuration = configuration
        self.attentionPolicy = AttentionPolicy(configuration: configuration)
        self.projectionPolicy = ProjectProjectionPolicy(configuration: configuration)
        self.requestRouter = AgentRequestRouter(configuration: configuration)
        self.attentionFormatter = ReminderFormatter(configuration: configuration)
        self.mainFormatter = MainReminderFormatter(configuration: configuration)
    }

    public func sync(now: Date = Date()) async throws -> SyncSummary {
        var summary = SyncSummary()

        if configuration.requestDispatchEnabled {
            do { try await dispatchAppleRequests(now: now, summary: &summary) }
            catch { summary.errors.append("dispatch requests: \(error)") }
        }

        var issues = try await source.fetchIssues()
        summary.fetchedIssues = issues.count

        // Closed issues may disappear from list output. Refresh any issue that still has
        // an active Apple projection so terminal state can be reconciled safely.
        let active = try persistence.activeProjections()
        let fetchedIDs = Set(issues.map(\.id))
        for projection in active where !fetchedIDs.contains(projection.issueID) {
            do { issues.append(try await source.fetchIssue(idOrKey: projection.issueKey)) }
            catch { summary.errors.append("refresh \(projection.issueKey): \(error)") }
        }

        issues = deduplicate(issues)
        issues = await hydrateLatestRuns(issues, summary: &summary)

        for issue in issues {
            do { try await reconcile(issue: issue, now: now, summary: &summary) }
            catch { summary.errors.append("\(issue.key): \(error)") }
        }

        summary.finishedAt = Date()
        try persistence.setMeta(key: "last_sync_finished_at", value: String(summary.finishedAt.timeIntervalSince1970))
        try persistence.setMeta(key: "last_sync_error_count", value: String(summary.errors.count))
        return summary
    }

    // MARK: - Apple -> Multica dispatch

    private func dispatchAppleRequests(now: Date, summary: inout SyncSummary) async throws {
        let requests = try await sink.scanRequests(in: configuration.requestListNames)
        for request in requests {
            do {
                if let existing = try persistence.request(requestID: request.id),
                   (existing.state == .dispatched || existing.state == .continued),
                   let key = existing.issueKey {
                    let issue = try await source.fetchIssue(idOrKey: key)
                    try await reconcileRecoveredRequestProjection(request, issue: issue, record: existing, now: now, summary: &summary)
                    continue
                }

                let route = try requestRouter.route(request)
                var record = AgentRequestRecord(requestID: request.id, receipt: request.receipt, sourceListName: request.listName, routeID: route.id, state: .pending, updatedAt: now)
                try persistence.upsertRequest(record)

                let issue: IssueSnapshot
                let isContinuation: Bool
                if let existingRef = requestRouter.existingIssueReference(from: request.url) {
                    issue = try await source.fetchIssue(idOrKey: existingRef)
                    if issue.assigneeName == nil, let agentID = route.defaultAgentID, !agentID.isEmpty {
                        // Assignment normally starts a run in Multica. For a continuation we
                        // want the follow-up comment to be the single trigger, so bind the
                        // agent without starting first and then add the comment.
                        try await source.assignIssueWithoutStarting(issueIDOrKey: issue.key, agentID: agentID)
                    }
                    let followUp = requestBody(request, prefix: "Follow-up from Apple Reminders")
                    try await source.addComment(issueIDOrKey: issue.key, content: followUp)
                    isContinuation = true
                } else {
                    let create = IssueCreateRequest(
                        requestID: request.id,
                        title: request.title,
                        description: requestBody(request, prefix: nil),
                        projectID: route.multicaProjectID,
                        agentID: route.defaultAgentID,
                        dueDate: request.dueDate
                    )
                    issue = try await source.createIssue(create)
                    isContinuation = false
                }

                let projectRoute = projectionPolicy.routeForIssue(issue, binding: nil) ?? route
                let targetList = projectRoute.appleListName
                let priorBinding = try persistence.binding(issueID: issue.id)
                var binding = priorBinding ?? IssueBinding(
                    issueID: issue.id,
                    issueKey: issue.key,
                    origin: isContinuation ? .multica : .apple,
                    routeID: projectRoute.id,
                    projectID: issue.projectID ?? projectRoute.multicaProjectID,
                    projectName: issue.projectName ?? projectRoute.multicaProjectName,
                    appleListName: targetList,
                    updatedAt: now
                )
                // A follow-up to a pre-existing Multica Issue does not retroactively make
                // that Issue Apple-origin. Preserve an existing binding when available.
                if !isContinuation { binding.origin = .apple }
                binding.routeID = projectRoute.id
                binding.projectID = issue.projectID ?? projectRoute.multicaProjectID
                binding.projectName = issue.projectName ?? projectRoute.multicaProjectName
                binding.appleListName = targetList
                binding.mainProjectionDismissed = false
                binding.updatedAt = now
                try persistence.upsertBinding(binding)

                record.issueID = issue.id
                record.issueKey = issue.key
                record.state = isContinuation ? .continued : .dispatched
                record.lastError = nil
                record.updatedAt = now
                try persistence.upsertRequest(record)

                let plan = projectionPolicy.plan(issue: issue, binding: binding)
                let existingMain = try persistence.projection(issueID: issue.id, kind: .mainIssue, generation: 0)
                if plan.shouldMaintainMain {
                    if existingMain == nil {
                        try await upsertMain(issue: issue, binding: binding, existingReceipt: request.receipt, now: now, summary: &summary)
                    } else if existingMain?.receipt?.calendarItemIdentifier != request.receipt.calendarItemIdentifier {
                        // A second Apple Reminder that continues an already-projected issue is a dispatch
                        // action, not a second Main task. Complete that request receipt after handoff.
                        try await sink.resolve(request.receipt, issueKey: issue.key, kind: .mainIssue, generation: 0)
                    }
                } else {
                    // In attention_only (or Multica-origin apple_origin_only continuation), the
                    // Apple Reminder represents the delegation action itself. Complete it once handoff succeeds.
                    try await sink.resolve(request.receipt, issueKey: issue.key, kind: .mainIssue, generation: 0)
                }

                if isContinuation { summary.continuedRequests += 1 }
                else { summary.dispatchedRequests += 1 }
            } catch {
                var record = (try? persistence.request(requestID: request.id)) ?? AgentRequestRecord(requestID: request.id, receipt: request.receipt, sourceListName: request.listName)
                record.state = .failed
                record.lastError = String(describing: error)
                record.updatedAt = now
                try? persistence.upsertRequest(record)
                summary.errors.append("request \(request.title): \(error)")
            }
        }
    }

    private func reconcileRecoveredRequestProjection(_ request: AgentRequestSnapshot, issue: IssueSnapshot, record: AgentRequestRecord, now: Date, summary: inout SyncSummary) async throws {
        let route = record.routeID.flatMap { id in configuration.projectRoutes.first(where: { $0.id == id }) }
        let priorBinding = try persistence.binding(issueID: issue.id)
        var binding = priorBinding ?? IssueBinding(
            issueID: issue.id,
            issueKey: issue.key,
            origin: record.state == .continued ? .multica : .apple,
            routeID: record.routeID,
            projectID: issue.projectID ?? route?.multicaProjectID,
            projectName: issue.projectName ?? route?.multicaProjectName,
            appleListName: route?.appleListName ?? request.listName,
            updatedAt: now
        )
        if record.state == .dispatched { binding.origin = .apple }
        binding.routeID = record.routeID ?? binding.routeID
        binding.projectID = issue.projectID ?? binding.projectID
        binding.projectName = issue.projectName ?? binding.projectName
        binding.appleListName = route?.appleListName ?? binding.appleListName
        binding.updatedAt = now
        try persistence.upsertBinding(binding)

        let plan = projectionPolicy.plan(issue: issue, binding: binding)
        let existingMain = try persistence.projection(issueID: issue.id, kind: .mainIssue, generation: 0)
        if plan.shouldMaintainMain {
            if existingMain == nil {
                try await upsertMain(issue: issue, binding: binding, existingReceipt: request.receipt, now: now, summary: &summary)
            } else if existingMain?.receipt?.calendarItemIdentifier != request.receipt.calendarItemIdentifier {
                try await sink.resolve(request.receipt, issueKey: issue.key, kind: .mainIssue, generation: 0)
            }
        } else {
            try await sink.resolve(request.receipt, issueKey: issue.key, kind: .mainIssue, generation: 0)
        }
    }

    private func requestBody(_ request: AgentRequestSnapshot, prefix: String?) -> String {
        var lines: [String] = []
        if let prefix { lines.append(prefix + ":") }
        lines.append(request.title)
        let notes = request.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { lines.append(""); lines.append(notes) }
        return lines.joined(separator: "\n")
    }

    // MARK: - Multica -> Apple reconciliation

    private func hydrateLatestRuns(_ input: [IssueSnapshot], summary: inout SyncSummary) async -> [IssueSnapshot] {
        let candidates = input.enumerated().filter { _, issue in
            switch issue.statusCategory {
            case .inReview, .blocked: return issue.latestRun == nil
            case .todo, .inProgress: return configuration.failureRemindersEnabled && issue.latestRun == nil
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
            } catch { summary.errors.append("runs \(issue.key): \(error)") }
        }
        return output
    }

    private func reconcile(issue: IssueSnapshot, now: Date, summary: inout SyncSummary) async throws {
        let previous = try persistence.observation(issueID: issue.id)
        let reviewGeneration = ReviewCycleDetector.nextGeneration(previous: previous, current: issue)
        let firstBlockedAt = ReviewCycleDetector.firstBlockedAt(previous: previous, current: issue, now: now)
        var observation = IssueObservation(
            issueID: issue.id,
            issueKey: issue.key,
            statusName: issue.statusName,
            statusCategory: issue.statusCategory,
            reviewGeneration: reviewGeneration,
            attentionGeneration: previous?.attentionGeneration ?? 0,
            latestRunID: issue.latestRun?.id,
            latestRunStatus: issue.latestRun?.status,
            payloadHash: previous?.payloadHash,
            observedUpdatedAt: issue.updatedAt,
            firstBlockedAt: firstBlockedAt,
            updatedAt: now
        )

        var binding = try persistence.binding(issueID: issue.id)
        if binding == nil {
            let route = configuration.route(for: issue)
            binding = IssueBinding(
                issueID: issue.id,
                issueKey: issue.key,
                origin: .multica,
                routeID: route?.id,
                projectID: issue.projectID,
                projectName: issue.projectName,
                appleListName: route?.appleListName ?? configuration.genericRequestListName,
                updatedAt: now
            )
            try persistence.upsertBinding(binding!)
        } else if var existingBinding = binding {
            existingBinding.issueKey = issue.key
            existingBinding.projectID = issue.projectID ?? existingBinding.projectID
            existingBinding.projectName = issue.projectName ?? existingBinding.projectName
            existingBinding.updatedAt = now
            try persistence.upsertBinding(existingBinding)
            binding = existingBinding
        }
        guard let currentBinding = binding else { return }

        if issue.statusCategory.isTerminal {
            try await resolveProjections(issueID: issue.id, kind: nil, summary: &summary, now: now)
            try persistence.upsertObservation(observation)
            return
        }

        let plan = projectionPolicy.plan(issue: issue, binding: currentBinding)
        if plan.shouldMaintainMain && !currentBinding.mainProjectionDismissed {
            try await reconcileMain(issue: issue, binding: currentBinding, now: now, summary: &summary)
        } else if !plan.shouldMaintainMain {
            // Route/mirror-mode changes are reconciled too: an active Main that is no longer
            // eligible is completed rather than left stale in the project list.
            try await resolveProjections(issueID: issue.id, kind: .mainIssue, summary: &summary, now: now)
        }

        let decision = attentionPolicy.decide(issue: issue, observation: observation, now: now)
        switch decision.action {
        case .resolveReminder, .none:
            try await resolveProjections(issueID: issue.id, kind: .humanAction, summary: &summary, now: now)
        case .createOrUpdateReminder:
            let generation = attentionGeneration(previous: previous, current: issue, decision: decision, reviewGeneration: reviewGeneration)
            observation.attentionGeneration = generation
            try await reconcileHumanAction(issue: issue, binding: currentBinding, decision: decision, generation: generation, now: now, summary: &summary)
        }

        try persistence.upsertObservation(observation)
    }

    private func reconcileMain(issue: IssueSnapshot, binding: IssueBinding, now: Date, summary: inout SyncSummary) async throws {
        var projection = try persistence.projection(issueID: issue.id, kind: .mainIssue, generation: 0)
        if var existing = projection, let receipt = existing.receipt {
            switch try await sink.state(of: receipt, issueKey: issue.key, kind: .mainIssue, generation: 0) {
            case .completed, .missing:
                var updatedBinding = binding
                updatedBinding.mainProjectionDismissed = true
                updatedBinding.updatedAt = now
                try persistence.upsertBinding(updatedBinding)
                existing.userAcknowledged = true
                existing.state = .acknowledged
                existing.updatedAt = now
                try persistence.upsertProjection(existing)
                summary.acknowledged += 1
                return
            case .pending: break
            }
        }
        let item = mainFormatter.makeItem(issue: issue, listName: binding.appleListName)
        let hash = mainFormatter.payloadHash(item)
        if projection?.payloadHash == hash, projection?.state == .active { return }
        let receipt = try await sink.upsert(item, existing: projection?.receipt)
        if projection == nil {
            projection = ReminderProjection(issueID: issue.id, issueKey: issue.key, kind: .mainIssue, generation: 0, listName: binding.appleListName)
        }
        projection?.receipt = receipt
        projection?.listName = binding.appleListName
        projection?.state = .active
        projection?.userAcknowledged = false
        projection?.payloadHash = hash
        projection?.updatedAt = now
        if let projection { try persistence.upsertProjection(projection) }
        summary.mainCreatedOrUpdated += 1
    }

    private func upsertMain(issue: IssueSnapshot, binding: IssueBinding, existingReceipt: ReminderReceipt?, now: Date, summary: inout SyncSummary) async throws {
        let item = mainFormatter.makeItem(issue: issue, listName: binding.appleListName)
        let hash = mainFormatter.payloadHash(item)
        let receipt = try await sink.upsert(item, existing: existingReceipt)
        let projection = ReminderProjection(
            issueID: issue.id,
            issueKey: issue.key,
            kind: .mainIssue,
            generation: 0,
            listName: binding.appleListName,
            receipt: receipt,
            state: .active,
            userAcknowledged: false,
            payloadHash: hash,
            createdAt: now,
            updatedAt: now
        )
        try persistence.upsertProjection(projection)
        summary.mainCreatedOrUpdated += 1
    }

    private func reconcileHumanAction(issue: IssueSnapshot, binding: IssueBinding, decision: AttentionDecision, generation: Int, now: Date, summary: inout SyncSummary) async throws {
        let item = attentionFormatter.makeItem(issue: issue, decision: decision, generation: generation, listName: binding.appleListName, now: now)
        let hash = attentionFormatter.payloadHash(item)
        var projection = try persistence.projection(issueID: issue.id, kind: .humanAction, generation: generation)
        if var existing = projection {
            if existing.userAcknowledged || existing.state == .acknowledged || existing.state == .dismissed { return }
            if let receipt = existing.receipt {
                switch try await sink.state(of: receipt, issueKey: existing.issueKey, kind: .humanAction, generation: existing.generation) {
                case .completed:
                    existing.userAcknowledged = true; existing.state = .acknowledged; existing.updatedAt = now
                    try persistence.upsertProjection(existing); summary.acknowledged += 1; return
                case .missing:
                    existing.userAcknowledged = true; existing.state = .dismissed; existing.updatedAt = now
                    try persistence.upsertProjection(existing); summary.acknowledged += 1; return
                case .pending: break
                }
            }
            if existing.payloadHash == hash, existing.state == .active { return }
        }

        let receipt = try await sink.upsert(item, existing: projection?.receipt)
        if projection == nil {
            projection = ReminderProjection(
                issueID: issue.id,
                issueKey: issue.key,
                kind: .humanAction,
                generation: generation,
                humanActionKind: attentionFormatter.actionKind(for: decision),
                listName: binding.appleListName
            )
        }
        projection?.receipt = receipt
        projection?.humanActionKind = attentionFormatter.actionKind(for: decision)
        projection?.listName = binding.appleListName
        projection?.state = .active
        projection?.userAcknowledged = false
        projection?.payloadHash = hash
        projection?.updatedAt = now
        if let projection { try persistence.upsertProjection(projection) }
        summary.humanActionsCreatedOrUpdated += 1
    }

    private func attentionGeneration(previous: IssueObservation?, current: IssueSnapshot, decision: AttentionDecision, reviewGeneration: Int) -> Int {
        if decision.reason == .reviewRequired { return max(1, reviewGeneration) }
        let old = previous?.attentionGeneration ?? 0
        switch decision.reason {
        case .blockedRequiresHuman:
            return previous?.statusCategory == .blocked ? max(old, 1) : old + 1
        case .failedRequiresHuman:
            if previous?.latestRunID == current.latestRun?.id, previous?.latestRunStatus == .failed { return max(old, 1) }
            return old + 1
        case .explicitAlways:
            if previous?.statusCategory == current.statusCategory, previous?.latestRunID == current.latestRun?.id { return max(old, 1) }
            return old + 1
        default: return max(old, 1)
        }
    }

    private func resolveProjections(issueID: String, kind: ReminderProjectionKind?, summary: inout SyncSummary, now: Date) async throws {
        let projections = try persistence.activeProjections(issueID: issueID).filter { kind == nil || $0.kind == kind }
        for var projection in projections {
            do {
                if let receipt = projection.receipt {
                    try await sink.resolve(receipt, issueKey: projection.issueKey, kind: projection.kind, generation: projection.generation)
                }
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
