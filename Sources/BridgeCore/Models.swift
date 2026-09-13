import Foundation

public enum IssueStatusCategory: String, Codable, CaseIterable, Sendable {
    case backlog
    case todo
    case inProgress = "in_progress"
    case inReview = "in_review"
    case done
    case blocked
    case cancelled
    case unknown

    public static func infer(name: String, explicitCategory: String? = nil) -> IssueStatusCategory {
        let candidates = [explicitCategory, name].compactMap {
            $0?.lowercased().replacingOccurrences(of: "-", with: "_").replacingOccurrences(of: " ", with: "_")
        }
        for value in candidates {
            switch value {
            case "backlog": return .backlog
            case "todo", "to_do", "open": return .todo
            case "in_progress", "progress", "doing", "rework": return .inProgress
            case "in_review", "review", "code_review", "qa", "verification": return .inReview
            case "done", "closed", "complete", "completed": return .done
            case "blocked", "waiting_for_user", "needs_input": return .blocked
            case "cancelled", "canceled": return .cancelled
            default: continue
            }
        }
        return .unknown
    }

    public var isTerminal: Bool { self == .done || self == .cancelled }
}

public enum RunStatus: String, Codable, Sendable {
    case deferred
    case queued
    case dispatched
    case starting
    case waitingLocalDirectory = "waiting_local_directory"
    case running
    case completed
    case failed
    case cancelled
    case unknown

    public init(normalizing raw: String?) {
        guard let value = raw?.lowercased().replacingOccurrences(of: "-", with: "_") else {
            self = .unknown
            return
        }
        switch value {
        case "deferred": self = .deferred
        case "queued": self = .queued
        case "dispatched": self = .dispatched
        case "starting": self = .starting
        case "waiting_local_directory": self = .waitingLocalDirectory
        case "running": self = .running
        case "completed", "complete", "succeeded", "success": self = .completed
        case "failed", "error": self = .failed
        case "cancelled", "canceled": self = .cancelled
        default: self = .unknown
        }
    }

    public var isActive: Bool {
        switch self {
        case .deferred, .queued, .dispatched, .starting, .waitingLocalDirectory, .running: return true
        default: return false
        }
    }

    public var isTerminal: Bool { !isActive && self != .unknown }
}

public enum IssuePriority: String, Codable, Sendable {
    case urgent, high, medium, low, none, unknown

    public init(normalizing raw: String?) {
        switch raw?.lowercased() {
        case "urgent": self = .urgent
        case "high": self = .high
        case "medium", "normal": self = .medium
        case "low": self = .low
        case nil, "", "none": self = .none
        default: self = .unknown
        }
    }
}

public struct RunSnapshot: Codable, Equatable, Sendable {
    public let id: String
    public let status: RunStatus
    public let createdAt: Date?
    public let startedAt: Date?
    public let completedAt: Date?
    /// Stable Multica failure reason code when available, for example
    /// `runtime_offline`, `queued_expired`, or `agent_error.provider_quota_limit`.
    public let failureReasonCode: String?
    public let errorMessage: String?
    public let waitReason: String?
    public let agentName: String?

    public init(id: String, status: RunStatus, createdAt: Date? = nil, startedAt: Date? = nil, completedAt: Date? = nil, failureReasonCode: String? = nil, errorMessage: String? = nil, waitReason: String? = nil, agentName: String? = nil) {
        self.id = id
        self.status = status
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.failureReasonCode = failureReasonCode
        self.errorMessage = errorMessage
        self.waitReason = waitReason
        self.agentName = agentName
    }
}

public struct IssueSnapshot: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let key: String
    public let title: String
    public let statusName: String
    public let statusCategory: IssueStatusCategory
    public let priority: IssuePriority
    public let labels: Set<String>
    public let assigneeName: String?
    public let projectID: String?
    public let projectName: String?
    public let workspaceSlug: String?
    public let updatedAt: Date?
    public let dueDate: Date?
    public let summary: String?
    public var latestRun: RunSnapshot?

    public init(id: String, key: String, title: String, statusName: String, statusCategory: IssueStatusCategory, priority: IssuePriority = .none, labels: Set<String> = [], assigneeName: String? = nil, projectID: String? = nil, projectName: String? = nil, workspaceSlug: String? = nil, updatedAt: Date? = nil, dueDate: Date? = nil, summary: String? = nil, latestRun: RunSnapshot? = nil) {
        self.id = id
        self.key = key
        self.title = title
        self.statusName = statusName
        self.statusCategory = statusCategory
        self.priority = priority
        self.labels = labels
        self.assigneeName = assigneeName
        self.projectID = projectID
        self.projectName = projectName
        self.workspaceSlug = workspaceSlug
        self.updatedAt = updatedAt
        self.dueDate = dueDate
        self.summary = summary
        self.latestRun = latestRun
    }
}

public struct MulticaProject: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public struct MulticaAgent: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public enum MirrorMode: String, Codable, CaseIterable, Hashable, Sendable {
    case allActive = "all_active"
    case appleOriginOnly = "apple_origin_only"
    case attentionOnly = "attention_only"
}

public struct ProjectRoute: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var appleListName: String
    public var multicaProjectID: String?
    public var multicaProjectName: String?
    public var defaultAgentID: String?
    public var defaultAgentName: String?
    public var mirrorMode: MirrorMode

    public init(id: String = UUID().uuidString, appleListName: String, multicaProjectID: String? = nil, multicaProjectName: String? = nil, defaultAgentID: String? = nil, defaultAgentName: String? = nil, mirrorMode: MirrorMode = .appleOriginOnly) {
        self.id = id
        self.appleListName = appleListName
        self.multicaProjectID = multicaProjectID
        self.multicaProjectName = multicaProjectName
        self.defaultAgentID = defaultAgentID
        self.defaultAgentName = defaultAgentName
        self.mirrorMode = mirrorMode
    }
}

public enum IssueOrigin: String, Codable, Sendable {
    case apple
    case multica
}

public struct IssueBinding: Codable, Equatable, Sendable {
    public let issueID: String
    public var issueKey: String
    public var origin: IssueOrigin
    public var routeID: String?
    public var projectID: String?
    public var projectName: String?
    public var appleListName: String
    public var mainProjectionDismissed: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(issueID: String, issueKey: String, origin: IssueOrigin, routeID: String? = nil, projectID: String? = nil, projectName: String? = nil, appleListName: String, mainProjectionDismissed: Bool = false, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.issueID = issueID
        self.issueKey = issueKey
        self.origin = origin
        self.routeID = routeID
        self.projectID = projectID
        self.projectName = projectName
        self.appleListName = appleListName
        self.mainProjectionDismissed = mainProjectionDismissed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum AttentionAction: String, Codable, Sendable {
    case none
    case createOrUpdateReminder = "create_or_update"
    case resolveReminder = "resolve"
}

public enum AttentionReason: String, Codable, Sendable {
    case suppressed
    case terminal
    case reviewRequired = "review_required"
    case blockedRequiresHuman = "blocked_requires_human"
    case failedRequiresHuman = "failed_requires_human"
    case explicitAlways = "explicit_always"
    case activeOrNoAction = "active_or_no_action"
}

public enum AttentionSeverity: String, Codable, Sendable {
    case normal
    case high
    case urgent
}

public struct AttentionDecision: Codable, Equatable, Sendable {
    public let action: AttentionAction
    public let reason: AttentionReason
    public let severity: AttentionSeverity

    public init(action: AttentionAction, reason: AttentionReason, severity: AttentionSeverity = .normal) {
        self.action = action
        self.reason = reason
        self.severity = severity
    }
}

public enum ReminderProjectionKind: String, Codable, Sendable {
    case mainIssue = "main_issue"
    case humanAction = "human_action"
}

public enum HumanActionKind: String, Codable, Sendable {
    case review
    case actionRequired = "action_required"
    case failed

    /// Reads v0.2 persisted values without keeping the old user-facing taxonomy alive.
    public static func fromPersistedValue(_ raw: String?) -> HumanActionKind? {
        switch raw {
        case "review": return .review
        case "action_required", "unblock", "explicit": return .actionRequired
        case "failed", "failure": return .failed
        default: return nil
        }
    }
}

public enum ReminderProjectionState: String, Codable, Sendable {
    case active
    case resolved
    case acknowledged
    case dismissed
    case pendingRetry = "pending_retry"
}

public enum ReminderRemoteState: String, Codable, Sendable {
    case pending
    case completed
    case missing
}

public struct ReminderReceipt: Codable, Equatable, Sendable {
    public let calendarItemIdentifier: String?
    public let externalIdentifier: String?

    public init(calendarItemIdentifier: String?, externalIdentifier: String? = nil) {
        self.calendarItemIdentifier = calendarItemIdentifier
        self.externalIdentifier = externalIdentifier
    }
}

public struct ReminderProjection: Codable, Equatable, Sendable {
    public let id: String
    public let issueID: String
    public let issueKey: String
    public let kind: ReminderProjectionKind
    public let generation: Int
    public var humanActionKind: HumanActionKind?
    public var listName: String
    public var receipt: ReminderReceipt?
    public var state: ReminderProjectionState
    public var userAcknowledged: Bool
    public var payloadHash: String?
    public let createdAt: Date
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, issueID: String, issueKey: String, kind: ReminderProjectionKind, generation: Int = 0, humanActionKind: HumanActionKind? = nil, listName: String, receipt: ReminderReceipt? = nil, state: ReminderProjectionState = .active, userAcknowledged: Bool = false, payloadHash: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.issueID = issueID
        self.issueKey = issueKey
        self.kind = kind
        self.generation = generation
        self.humanActionKind = humanActionKind
        self.listName = listName
        self.receipt = receipt
        self.state = state
        self.userAcknowledged = userAcknowledged
        self.payloadHash = payloadHash
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct IssueObservation: Codable, Equatable, Sendable {
    public let issueID: String
    public var issueKey: String
    public var statusName: String
    public var statusCategory: IssueStatusCategory
    public var reviewGeneration: Int
    public var attentionGeneration: Int
    public var latestRunID: String?
    public var latestRunStatus: RunStatus?
    public var payloadHash: String?
    public var observedUpdatedAt: Date?
    public var firstBlockedAt: Date?
    public var updatedAt: Date

    public init(issueID: String, issueKey: String, statusName: String, statusCategory: IssueStatusCategory, reviewGeneration: Int = 0, attentionGeneration: Int = 0, latestRunID: String? = nil, latestRunStatus: RunStatus? = nil, payloadHash: String? = nil, observedUpdatedAt: Date? = nil, firstBlockedAt: Date? = nil, updatedAt: Date = Date()) {
        self.issueID = issueID
        self.issueKey = issueKey
        self.statusName = statusName
        self.statusCategory = statusCategory
        self.reviewGeneration = reviewGeneration
        self.attentionGeneration = attentionGeneration
        self.latestRunID = latestRunID
        self.latestRunStatus = latestRunStatus
        self.payloadHash = payloadHash
        self.observedUpdatedAt = observedUpdatedAt
        self.firstBlockedAt = firstBlockedAt
        self.updatedAt = updatedAt
    }
}

public enum ReminderItemKind: String, Codable, Sendable {
    case main
    case humanAction = "human_action"
}

public struct ReminderItem: Codable, Equatable, Sendable {
    public let issueID: String
    public let issueKey: String
    public let kind: ReminderItemKind
    public let generation: Int
    public let listName: String
    public let title: String
    public let notes: String
    public let url: URL?
    public let priority: AttentionSeverity
    public let dueDate: Date?
    public let alarmDate: Date?

    public init(issueID: String, issueKey: String, kind: ReminderItemKind, generation: Int = 0, listName: String, title: String, notes: String, url: URL?, priority: AttentionSeverity = .normal, dueDate: Date? = nil, alarmDate: Date? = nil) {
        self.issueID = issueID
        self.issueKey = issueKey
        self.kind = kind
        self.generation = generation
        self.listName = listName
        self.title = title
        self.notes = notes
        self.url = url
        self.priority = priority
        self.dueDate = dueDate
        self.alarmDate = alarmDate
    }
}

public struct AgentRequestSnapshot: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let receipt: ReminderReceipt
    public let listName: String
    public let title: String
    public let notes: String
    public let url: URL?
    public let dueDate: Date?
    public let priority: Int

    public init(id: String, receipt: ReminderReceipt, listName: String, title: String, notes: String, url: URL?, dueDate: Date?, priority: Int = 0) {
        self.id = id
        self.receipt = receipt
        self.listName = listName
        self.title = title
        self.notes = notes
        self.url = url
        self.dueDate = dueDate
        self.priority = priority
    }
}

public enum AgentRequestState: String, Codable, Sendable {
    case pending
    case dispatched
    case continued
    case cancelled
    case failed
}

public struct AgentRequestRecord: Codable, Equatable, Sendable {
    public let requestID: String
    public var receipt: ReminderReceipt
    public var sourceListName: String
    public var routeID: String?
    public var issueID: String?
    public var issueKey: String?
    public var state: AgentRequestState
    public var lastError: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(requestID: String, receipt: ReminderReceipt, sourceListName: String, routeID: String? = nil, issueID: String? = nil, issueKey: String? = nil, state: AgentRequestState = .pending, lastError: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.requestID = requestID
        self.receipt = receipt
        self.sourceListName = sourceListName
        self.routeID = routeID
        self.issueID = issueID
        self.issueKey = issueKey
        self.state = state
        self.lastError = lastError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct IssueCreateRequest: Codable, Equatable, Sendable {
    public let requestID: String
    public let title: String
    public let description: String
    public let projectID: String?
    public let agentID: String?
    public let dueDate: Date?

    public init(requestID: String, title: String, description: String, projectID: String?, agentID: String?, dueDate: Date?) {
        self.requestID = requestID
        self.title = title
        self.description = description
        self.projectID = projectID
        self.agentID = agentID
        self.dueDate = dueDate
    }
}

public struct SyncSummary: Codable, Equatable, Sendable {
    public var fetchedIssues: Int = 0
    public var dispatchedRequests: Int = 0
    public var continuedRequests: Int = 0
    public var mainCreatedOrUpdated: Int = 0
    public var humanActionsCreatedOrUpdated: Int = 0
    public var reviewApprovals: Int = 0
    public var resolved: Int = 0
    public var acknowledged: Int = 0
    public var errors: [String] = []
    public var finishedAt: Date = Date()

    /// Backwards-compatible aggregate used by the v0.1 UI/logging.
    public var createdOrUpdated: Int {
        get { mainCreatedOrUpdated + humanActionsCreatedOrUpdated }
        set { humanActionsCreatedOrUpdated = max(0, newValue - mainCreatedOrUpdated) }
    }

    public init() {}
}

// MARK: - v0.1 source compatibility during v0.2 migration

public typealias HumanAttentionItem = ReminderItem

public extension ReminderItem {
    init(issueID: String, issueKey: String, reviewGeneration: Int, title: String, notes: String, url: URL?, priority: AttentionSeverity, dueDate: Date?) {
        self.init(issueID: issueID, issueKey: issueKey, kind: .humanAction, generation: reviewGeneration, listName: "Agent Requests", title: title, notes: notes, url: url, priority: priority, dueDate: dueDate, alarmDate: nil)
    }

    var reviewGeneration: Int { generation }
}

public extension ReminderProjection {
    var reviewGeneration: Int { generation }
}

public extension ReminderProjection {
    init(issueID: String, issueKey: String, reviewGeneration: Int, receipt: ReminderReceipt? = nil, state: ReminderProjectionState = .active, userAcknowledged: Bool = false, payloadHash: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.init(issueID: issueID, issueKey: issueKey, kind: .humanAction, generation: reviewGeneration, humanActionKind: .review, listName: "Agent Requests", receipt: receipt, state: state, userAcknowledged: userAcknowledged, payloadHash: payloadHash, createdAt: createdAt, updatedAt: updatedAt)
    }
}
