import Foundation

public protocol MulticaSource {
    func fetchIssues() async throws -> [IssueSnapshot]
    func fetchIssue(idOrKey: String) async throws -> IssueSnapshot
    func fetchRuns(issueIDOrKey: String) async throws -> [RunSnapshot]
    func authStatus() async throws -> String
    func version() async throws -> String
}

@MainActor
public protocol ReminderSink: AnyObject {
    func requestAccess() async throws -> Bool
    func upsert(_ item: HumanAttentionItem, existing: ReminderReceipt?) async throws -> ReminderReceipt
    func resolve(_ receipt: ReminderReceipt, issueKey: String, reviewGeneration: Int) async throws
    func state(of receipt: ReminderReceipt, issueKey: String, reviewGeneration: Int) async throws -> ReminderRemoteState
    func createTestReminder(title: String, notes: String) async throws -> ReminderReceipt
}

public protocol BridgePersistence: AnyObject {
    func migrate() throws
    func observation(issueID: String) throws -> IssueObservation?
    func upsertObservation(_ observation: IssueObservation) throws
    func projection(issueID: String, reviewGeneration: Int) throws -> ReminderProjection?
    func activeProjections(issueID: String) throws -> [ReminderProjection]
    func activeProjections() throws -> [ReminderProjection]
    func upsertProjection(_ projection: ReminderProjection) throws
    func setMeta(key: String, value: String) throws
    func meta(key: String) throws -> String?
}
