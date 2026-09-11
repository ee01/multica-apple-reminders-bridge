import XCTest
@testable import BridgeCore

final class AttentionPolicyTests: XCTestCase {
    private var config: BridgeConfiguration { BridgeConfiguration(blockedGraceSeconds: 600) }

    func testInReviewCreatesReminder() {
        let decision = AttentionPolicy(configuration: config).decide(issue: issue(.inReview), observation: nil)
        XCTAssertEqual(decision.action, .createOrUpdateReminder)
        XCTAssertEqual(decision.reason, .reviewRequired)
    }

    func testSuppressionWinsOverReview() {
        var c = config
        c.suppressionLabels = ["no-reminder"]
        let decision = AttentionPolicy(configuration: c).decide(issue: issue(.inReview, labels: ["no-reminder"]), observation: nil)
        XCTAssertEqual(decision.action, .none)
        XCTAssertEqual(decision.reason, .suppressed)
    }

    func testDoneResolves() {
        let decision = AttentionPolicy(configuration: config).decide(issue: issue(.done), observation: nil)
        XCTAssertEqual(decision.action, .resolveReminder)
    }

    func testBlockedWaitsDuringGraceThenReminds() {
        let now = Date(timeIntervalSince1970: 1_000)
        let observation = IssueObservation(issueID: "1", issueKey: "MUL-1", statusName: "blocked", statusCategory: .blocked, firstBlockedAt: now.addingTimeInterval(-601))
        let decision = AttentionPolicy(configuration: config).decide(issue: issue(.blocked), observation: observation, now: now)
        XCTAssertEqual(decision.reason, .blockedRequiresHuman)
        XCTAssertEqual(decision.action, .createOrUpdateReminder)
    }

    func testBlockedActiveRunDoesNotRemind() {
        var value = issue(.blocked)
        value.latestRun = RunSnapshot(id: "run", status: .queued)
        let observation = IssueObservation(issueID: "1", issueKey: "MUL-1", statusName: "blocked", statusCategory: .blocked, firstBlockedAt: Date(timeIntervalSince1970: 0))
        let decision = AttentionPolicy(configuration: config).decide(issue: value, observation: observation, now: Date(timeIntervalSince1970: 9999))
        XCTAssertEqual(decision.action, .none)
    }

    func testFailedRunRemindsWhenOpen() {
        var value = issue(.todo)
        value.latestRun = RunSnapshot(id: "run", status: .failed)
        let decision = AttentionPolicy(configuration: config).decide(issue: value, observation: nil)
        XCTAssertEqual(decision.reason, .failedRequiresHuman)
    }

    func testUrgentLabelRaisesSeverity() {
        let decision = AttentionPolicy(configuration: config).decide(issue: issue(.inReview, labels: ["reminder-urgent"]), observation: nil)
        XCTAssertEqual(decision.severity, .urgent)
    }

    private func issue(_ category: IssueStatusCategory, labels: Set<String> = []) -> IssueSnapshot {
        IssueSnapshot(id: "1", key: "MUL-1", title: "Title", statusName: category.rawValue, statusCategory: category, labels: labels)
    }
}
