import XCTest
@testable import BridgeCore

final class ReminderNotesTests: XCTestCase {
    func testHumanActionUsesReminderURLFieldForMulticaLinkAndLatestAsks() {
        var issue = IssueSnapshot(
            id: "uuid-1",
            key: "E-5",
            title: "Fix gantt rename scroll",
            statusName: "in_review",
            statusCategory: .inReview,
            workspaceSlug: "eeee",
            issueDescription: "## User request\n\nOriginal long description that should be skipped when later asks exist."
        )
        issue.recentMemberAsks = [
            "我在 backlog 创建的一个 item，拖拽到 gantt 上的时候 bar 会丢失 end date",
            "怎么样了？"
        ]
        let formatter = ReminderFormatter(configuration: BridgeConfiguration(workspaceSlug: "eeee"))
        let item = formatter.makeItem(
            issue: issue,
            decision: AttentionDecision(action: .createOrUpdateReminder, reason: .reviewRequired, severity: .normal),
            generation: 2,
            listName: "Agent Requests",
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(item.url?.absoluteString, "https://multica.ai/eeee/issues/E-5")
        XCTAssertFalse(item.notes.contains("https://multica.ai"))
        XCTAssertTrue(item.notes.contains("Latest from you:"))
        XCTAssertTrue(item.notes.contains("丢失 end date"))
        XCTAssertTrue(item.notes.contains("怎么样了？"))
        XCTAssertFalse(item.notes.contains("Original long description"))
        XCTAssertFalse(item.notes.contains("Latest run:"))
        XCTAssertTrue(item.notes.contains("Review round: #2"))
    }

    func testMainReminderUsesURLFieldNotNotesForMulticaLink() {
        let issue = IssueSnapshot(
            id: "uuid-2",
            key: "E-6",
            title: "Ship feature",
            statusName: "in_progress",
            statusCategory: .inProgress,
            workspaceSlug: "eeee",
            projectName: "Personal AI"
        )
        let item = MainReminderFormatter(configuration: BridgeConfiguration(workspaceSlug: "eeee")).makeItem(
            issue: issue,
            listName: "Personal AI"
        )
        XCTAssertEqual(item.url?.absoluteString, "https://multica.ai/eeee/issues/E-6")
        XCTAssertFalse(item.notes.contains("https://multica.ai"))
        XCTAssertTrue(item.notes.contains("Multica: E-6"))
    }

    func testHumanActionFallsBackToDescriptionWhenThereAreNoMemberComments() {
        let issue = IssueSnapshot(
            id: "uuid-1",
            key: "E-5",
            title: "Fix gantt",
            statusName: "in_review",
            statusCategory: .inReview,
            workspaceSlug: "eeee",
            issueDescription: "## User request\n\n1. 双击改名时滚动到最左侧"
        )
        let item = ReminderFormatter(configuration: BridgeConfiguration()).makeItem(
            issue: issue,
            decision: AttentionDecision(action: .createOrUpdateReminder, reason: .reviewRequired, severity: .normal),
            generation: 1,
            listName: "Agent Requests",
            now: Date()
        )
        XCTAssertTrue(item.notes.contains("What this is:"))
        XCTAssertTrue(item.notes.contains("双击改名"))
        XCTAssertFalse(item.notes.contains("## User request"))
    }

    func testNotifyMeScheduleAppliesToReviewAndFailedButNotBlocked() {
        let now = Date(timeIntervalSince1970: 1_000)
        let configuration = BridgeConfiguration(reminderAlarmSchedule: .after1Hour, reminderAlarmDelaySeconds: 3_600)
        let formatter = ReminderFormatter(configuration: configuration)
        let issue = IssueSnapshot(id: "1", key: "MUL-1", title: "Need input", statusName: "blocked", statusCategory: .blocked)

        let review = formatter.makeItem(
            issue: issue,
            decision: AttentionDecision(action: .createOrUpdateReminder, reason: .reviewRequired),
            generation: 1,
            listName: "Agent Requests",
            now: now
        )
        let blocked = formatter.makeItem(
            issue: issue,
            decision: AttentionDecision(action: .createOrUpdateReminder, reason: .blockedRequiresHuman),
            generation: 1,
            listName: "Agent Requests",
            now: now
        )
        let failed = formatter.makeItem(
            issue: issue,
            decision: AttentionDecision(action: .createOrUpdateReminder, reason: .failedRequiresHuman),
            generation: 1,
            listName: "Agent Requests",
            now: now
        )

        XCTAssertEqual(review.alarmDate, now.addingTimeInterval(3_600))
        XCTAssertEqual(blocked.alarmDate, now)
        XCTAssertEqual(failed.alarmDate, now.addingTimeInterval(3_600))
    }

    func testParsesMemberCommentsNewestFirstThenReturnsChronologicalAsks() throws {
        let json = """
        [
          {"id":"1","author_type":"agent","content":"已完成全部改动","created_at":"2026-09-14T09:00:00Z"},
          {"id":"2","author_type":"member","content":"bar 会丢失 end date","created_at":"2026-09-14T09:08:00Z"},
          {"id":"3","author_type":"member","content":"怎么样了？","created_at":"2026-09-14T09:13:00Z"}
        ]
        """.data(using: .utf8)!
        let comments = try MulticaJSONParser.parseComments(json)
        XCTAssertEqual(comments.count, 3)
        let human = comments.filter(\.isHumanAuthor).sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        let asks = Array(human.prefix(2).reversed().map(\.content))
        XCTAssertEqual(asks, ["bar 会丢失 end date", "怎么样了？"])
    }
}
