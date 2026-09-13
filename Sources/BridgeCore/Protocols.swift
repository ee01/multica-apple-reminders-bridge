import Foundation

public enum BridgeCapabilityError: Error, CustomStringConvertible {
    case unsupported(String)

    public var description: String {
        switch self { case .unsupported(let value): return "Unsupported bridge capability: \(value)" }
    }
}

public protocol MulticaSource {
    func fetchIssues() async throws -> [IssueSnapshot]
    func fetchIssue(idOrKey: String) async throws -> IssueSnapshot
    func fetchRuns(issueIDOrKey: String) async throws -> [RunSnapshot]
    func authStatus() async throws -> String
    func version() async throws -> String

    func createIssue(_ request: IssueCreateRequest) async throws -> IssueSnapshot
    func findIssue(bridgeRequestID: String) async throws -> IssueSnapshot?
    func assignIssue(issueIDOrKey: String, agentID: String) async throws
    func assignIssueWithoutStarting(issueIDOrKey: String, agentID: String) async throws
    func addComment(issueIDOrKey: String, content: String) async throws
    func setIssueStatus(issueIDOrKey: String, statusKey: String) async throws
    func listProjects() async throws -> [MulticaProject]
    func listAgents() async throws -> [MulticaAgent]
}

public extension MulticaSource {
    func createIssue(_ request: IssueCreateRequest) async throws -> IssueSnapshot { throw BridgeCapabilityError.unsupported("createIssue") }
    func findIssue(bridgeRequestID: String) async throws -> IssueSnapshot? { nil }
    func assignIssue(issueIDOrKey: String, agentID: String) async throws { throw BridgeCapabilityError.unsupported("assignIssue") }
    func assignIssueWithoutStarting(issueIDOrKey: String, agentID: String) async throws { try await assignIssue(issueIDOrKey: issueIDOrKey, agentID: agentID) }
    func addComment(issueIDOrKey: String, content: String) async throws { throw BridgeCapabilityError.unsupported("addComment") }
    func setIssueStatus(issueIDOrKey: String, statusKey: String) async throws { throw BridgeCapabilityError.unsupported("setIssueStatus") }
    func listProjects() async throws -> [MulticaProject] { [] }
    func listAgents() async throws -> [MulticaAgent] { [] }
}

@MainActor
public protocol ReminderSink: AnyObject {
    func requestAccess() async throws -> Bool
    func ensureLists(_ listNames: Set<String>) async throws
    func upsert(_ item: ReminderItem, existing: ReminderReceipt?) async throws -> ReminderReceipt
    func resolve(_ receipt: ReminderReceipt, issueKey: String, kind: ReminderProjectionKind, generation: Int) async throws
    func state(of receipt: ReminderReceipt, issueKey: String, kind: ReminderProjectionKind, generation: Int) async throws -> ReminderRemoteState
    func scanRequests(in listNames: Set<String>) async throws -> [AgentRequestSnapshot]
    func createTestReminder(title: String, notes: String) async throws -> ReminderReceipt
}

public extension ReminderSink {
    func ensureLists(_ listNames: Set<String>) async throws {}

    func resolve(_ receipt: ReminderReceipt, issueKey: String, reviewGeneration: Int) async throws {
        try await resolve(receipt, issueKey: issueKey, kind: .humanAction, generation: reviewGeneration)
    }

    func state(of receipt: ReminderReceipt, issueKey: String, reviewGeneration: Int) async throws -> ReminderRemoteState {
        try await state(of: receipt, issueKey: issueKey, kind: .humanAction, generation: reviewGeneration)
    }

    func scanRequests(in listNames: Set<String>) async throws -> [AgentRequestSnapshot] { [] }
}

public protocol BridgePersistence: AnyObject {
    func migrate() throws
    func observation(issueID: String) throws -> IssueObservation?
    func upsertObservation(_ observation: IssueObservation) throws

    func binding(issueID: String) throws -> IssueBinding?
    func binding(issueKey: String) throws -> IssueBinding?
    func upsertBinding(_ binding: IssueBinding) throws

    func projection(issueID: String, kind: ReminderProjectionKind, generation: Int) throws -> ReminderProjection?
    func projections(issueID: String, kind: ReminderProjectionKind?) throws -> [ReminderProjection]
    func activeProjections(issueID: String) throws -> [ReminderProjection]
    func activeProjections() throws -> [ReminderProjection]
    func upsertProjection(_ projection: ReminderProjection) throws

    func request(requestID: String) throws -> AgentRequestRecord?
    func upsertRequest(_ request: AgentRequestRecord) throws

    func setMeta(key: String, value: String) throws
    func meta(key: String) throws -> String?
}

public extension BridgePersistence {
    func projection(issueID: String, reviewGeneration: Int) throws -> ReminderProjection? {
        try projection(issueID: issueID, kind: .humanAction, generation: reviewGeneration)
    }
}
