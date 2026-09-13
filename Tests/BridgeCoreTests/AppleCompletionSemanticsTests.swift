import XCTest
@testable import BridgeCore

@MainActor
final class AppleCompletionSemanticsTests: XCTestCase {
    func testCompletingMainDismissesAppleProjectionWithoutClosingMulticaIssue() async throws {
        let route = ProjectRoute(appleListName: "Agent · Personal AI", multicaProjectID: "p1")
        let source = MutableIssueSource(issues: [issue(.inProgress)])
        let sink = InMemoryReminderSink()
        let db = try makeDB()
        try db.upsertBinding(IssueBinding(issueID: "1", issueKey: "MUL-1", origin: .apple, routeID: route.id, projectID: "p1", appleListName: route.appleListName))
        let engine = SyncEngine(source: source, sink: sink, persistence: db, configuration: BridgeConfiguration(projectRoutes: [route], requestDispatchEnabled: false))

        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1000))
        let main = try XCTUnwrap(db.projection(issueID: "1", kind: .mainIssue, generation: 0))
        let mainID = try XCTUnwrap(main.receipt?.calendarItemIdentifier)
        sink.markCompleted(id: mainID)

        let afterCompletion = try await engine.sync(now: Date(timeIntervalSince1970: 1010))
        XCTAssertEqual(afterCompletion.acknowledged, 1)
        XCTAssertEqual(try db.binding(issueID: "1")?.mainProjectionDismissed, true)
        XCTAssertEqual(try db.projection(issueID: "1", kind: .mainIssue, generation: 0)?.state, .acknowledged)

        // The issue is still active in Multica. The Bridge must not recreate Main.
        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1020))
        XCTAssertEqual(sink.records.count, 1)
        XCTAssertEqual(sink.records[mainID]?.state, .completed)
    }

    func testDismissedMainDoesNotPreventLaterHumanActionSibling() async throws {
        let route = ProjectRoute(appleListName: "Agent · Personal AI", multicaProjectID: "p1")
        let source = MutableIssueSource(issues: [issue(.inProgress)])
        let sink = InMemoryReminderSink()
        let db = try makeDB()
        try db.upsertBinding(IssueBinding(issueID: "1", issueKey: "MUL-1", origin: .apple, routeID: route.id, projectID: "p1", appleListName: route.appleListName))
        let engine = SyncEngine(source: source, sink: sink, persistence: db, configuration: BridgeConfiguration(projectRoutes: [route], requestDispatchEnabled: false))

        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1000))
        let mainID = try XCTUnwrap(try db.projection(issueID: "1", kind: .mainIssue, generation: 0)?.receipt?.calendarItemIdentifier)
        sink.markCompleted(id: mainID)
        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1010))

        await source.setIssues([issue(.inReview, run: RunSnapshot(id: "r1", status: .completed))])
        let reviewSync = try await engine.sync(now: Date(timeIntervalSince1970: 1020))

        XCTAssertEqual(reviewSync.humanActionsCreatedOrUpdated, 1)
        XCTAssertEqual(try db.binding(issueID: "1")?.mainProjectionDismissed, true)
        XCTAssertNotNil(try db.projection(issueID: "1", kind: .humanAction, generation: 1))
        XCTAssertEqual(sink.records.count, 2)
    }

    func testCompletingHumanActionAcknowledgesOnlyThatReviewRound() async throws {
        let route = ProjectRoute(appleListName: "Agent · Personal AI", multicaProjectID: "p1")
        let source = MutableIssueSource(issues: [issue(.inReview, run: RunSnapshot(id: "r0", status: .completed))])
        let sink = InMemoryReminderSink()
        let db = try makeDB()
        try db.upsertBinding(IssueBinding(issueID: "1", issueKey: "MUL-1", origin: .apple, routeID: route.id, projectID: "p1", appleListName: route.appleListName))
        let engine = SyncEngine(source: source, sink: sink, persistence: db, configuration: BridgeConfiguration(projectRoutes: [route], requestDispatchEnabled: false, reviewCompletionBehavior: .acknowledgeOnly))

        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1000))
        let main = try XCTUnwrap(db.projection(issueID: "1", kind: .mainIssue, generation: 0))
        let review1 = try XCTUnwrap(db.projection(issueID: "1", kind: .humanAction, generation: 1))
        let reviewID = try XCTUnwrap(review1.receipt?.calendarItemIdentifier)
        sink.markCompleted(id: reviewID)

        let acknowledged = try await engine.sync(now: Date(timeIntervalSince1970: 1010))
        XCTAssertEqual(acknowledged.acknowledged, 1)
        XCTAssertEqual(try db.projection(issueID: "1", kind: .humanAction, generation: 1)?.state, .acknowledged)
        let mainState = try await sink.state(of: main.receipt!, issueKey: "MUL-1", kind: .mainIssue, generation: 0)
        XCTAssertEqual(mainState, .pending)

        // Same review state must not recreate the acknowledged sibling.
        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1020))
        XCTAssertEqual(sink.records.count, 2)

        // A real rework + new delivery creates a new review round.
        await source.setIssues([issue(.inReview, run: RunSnapshot(id: "r1", status: .running))])
        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1030))
        await source.setIssues([issue(.inReview, run: RunSnapshot(id: "r1", status: .completed))])
        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1040))
        XCTAssertNotNil(try db.projection(issueID: "1", kind: .humanAction, generation: 2))
        XCTAssertEqual(sink.records.count, 3)
    }

    func testCompletingCurrentReviewApprovesMulticaIssueAndCompletesMainByDefault() async throws {
        let route = ProjectRoute(appleListName: "Agent · Personal AI", multicaProjectID: "p1")
        let source = MutableIssueSource(issues: [issue(.inReview, run: RunSnapshot(id: "r0", status: .completed))])
        let sink = InMemoryReminderSink()
        let db = try makeDB()
        try db.upsertBinding(IssueBinding(issueID: "1", issueKey: "MUL-1", origin: .apple, routeID: route.id, projectID: "p1", appleListName: route.appleListName))
        let engine = SyncEngine(source: source, sink: sink, persistence: db, configuration: BridgeConfiguration(projectRoutes: [route], requestDispatchEnabled: false))

        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1000))
        let main = try XCTUnwrap(db.projection(issueID: "1", kind: .mainIssue, generation: 0))
        let review = try XCTUnwrap(db.projection(issueID: "1", kind: .humanAction, generation: 1))
        sink.markCompleted(id: try XCTUnwrap(review.receipt?.calendarItemIdentifier))

        let result = try await engine.sync(now: Date(timeIntervalSince1970: 1010))

        XCTAssertEqual(result.reviewApprovals, 1)
        let updates = await source.recordedStatusUpdates()
        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates[0].0, "MUL-1")
        XCTAssertEqual(updates[0].1, "done")
        XCTAssertEqual(try db.observation(issueID: "1")?.statusCategory, .done)
        XCTAssertEqual(try db.projection(issueID: "1", kind: .humanAction, generation: 1)?.state, .resolved)
        let mainState = try await sink.state(of: main.receipt!, issueKey: "MUL-1", kind: .mainIssue, generation: 0)
        XCTAssertEqual(mainState, .completed)
    }

    func testCompletingActionRequiredAcknowledgesWithoutChangingMulticaStatus() async throws {
        let route = ProjectRoute(appleListName: "Agent · Personal AI", multicaProjectID: "p1")
        let source = MutableIssueSource(issues: [issue(.blocked)])
        let sink = InMemoryReminderSink()
        let db = try makeDB()
        try db.upsertBinding(IssueBinding(issueID: "1", issueKey: "MUL-1", origin: .apple, routeID: route.id, projectID: "p1", appleListName: route.appleListName))
        let config = BridgeConfiguration(projectRoutes: [route], requestDispatchEnabled: false, blockedGraceSeconds: 0)
        let engine = SyncEngine(source: source, sink: sink, persistence: db, configuration: config)

        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1000))
        let action = try XCTUnwrap(db.projection(issueID: "1", kind: .humanAction, generation: 1))
        XCTAssertEqual(action.humanActionKind, .actionRequired)
        sink.markCompleted(id: try XCTUnwrap(action.receipt?.calendarItemIdentifier))

        let result = try await engine.sync(now: Date(timeIntervalSince1970: 1010))
        XCTAssertEqual(result.acknowledged, 1)
        let actionUpdates = await source.recordedStatusUpdates()
        XCTAssertTrue(actionUpdates.isEmpty)
        XCTAssertEqual(try db.projection(issueID: "1", kind: .humanAction, generation: 1)?.state, .acknowledged)
    }

    func testCompletingFailedAcknowledgesWithoutRetryOrStatusChange() async throws {
        let route = ProjectRoute(appleListName: "Agent · Personal AI", multicaProjectID: "p1")
        let failedRun = RunSnapshot(id: "r-failed", status: .failed, failureReasonCode: "agent_error.provider_quota_limit")
        let source = MutableIssueSource(issues: [issue(.todo, run: failedRun)])
        let sink = InMemoryReminderSink()
        let db = try makeDB()
        try db.upsertBinding(IssueBinding(issueID: "1", issueKey: "MUL-1", origin: .apple, routeID: route.id, projectID: "p1", appleListName: route.appleListName))
        let engine = SyncEngine(source: source, sink: sink, persistence: db, configuration: BridgeConfiguration(projectRoutes: [route], requestDispatchEnabled: false))

        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1000))
        let failed = try XCTUnwrap(db.projection(issueID: "1", kind: .humanAction, generation: 1))
        XCTAssertEqual(failed.humanActionKind, .failed)
        sink.markCompleted(id: try XCTUnwrap(failed.receipt?.calendarItemIdentifier))

        let result = try await engine.sync(now: Date(timeIntervalSince1970: 1010))
        XCTAssertEqual(result.acknowledged, 1)
        let failureUpdates = await source.recordedStatusUpdates()
        XCTAssertTrue(failureUpdates.isEmpty)
        XCTAssertEqual(try db.projection(issueID: "1", kind: .humanAction, generation: 1)?.state, .acknowledged)
    }

    func testFailedReviewApprovalReopensReminderInsteadOfSilentlyLosingApproval() async throws {
        let route = ProjectRoute(appleListName: "Agent · Personal AI", multicaProjectID: "p1")
        let source = FailingStatusSource(issue: issue(.inReview, run: RunSnapshot(id: "r0", status: .completed)))
        let sink = InMemoryReminderSink()
        let db = try makeDB()
        try db.upsertBinding(IssueBinding(issueID: "1", issueKey: "MUL-1", origin: .apple, routeID: route.id, projectID: "p1", appleListName: route.appleListName))
        let engine = SyncEngine(source: source, sink: sink, persistence: db, configuration: BridgeConfiguration(projectRoutes: [route], requestDispatchEnabled: false))

        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1000))
        let review = try XCTUnwrap(db.projection(issueID: "1", kind: .humanAction, generation: 1))
        let reviewID = try XCTUnwrap(review.receipt?.calendarItemIdentifier)
        sink.markCompleted(id: reviewID)

        let result = try await engine.sync(now: Date(timeIntervalSince1970: 1010))
        XCTAssertEqual(result.reviewApprovals, 0)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertEqual(try db.projection(issueID: "1", kind: .humanAction, generation: 1)?.state, .active)
        let remote = try await sink.state(of: review.receipt!, issueKey: "MUL-1", kind: .humanAction, generation: 1)
        XCTAssertEqual(remote, .pending)
    }

    func testDeletingMainAlsoDismissesOnlyAppleProjection() async throws {
        let route = ProjectRoute(appleListName: "Agent · Personal AI", multicaProjectID: "p1")
        let source = MutableIssueSource(issues: [issue(.inProgress)])
        let sink = InMemoryReminderSink()
        let db = try makeDB()
        try db.upsertBinding(IssueBinding(issueID: "1", issueKey: "MUL-1", origin: .apple, routeID: route.id, projectID: "p1", appleListName: route.appleListName))
        let engine = SyncEngine(source: source, sink: sink, persistence: db, configuration: BridgeConfiguration(projectRoutes: [route], requestDispatchEnabled: false))

        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1000))
        let mainID = try XCTUnwrap(try db.projection(issueID: "1", kind: .mainIssue, generation: 0)?.receipt?.calendarItemIdentifier)
        sink.delete(id: mainID)
        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1010))

        XCTAssertEqual(try db.binding(issueID: "1")?.mainProjectionDismissed, true)
        XCTAssertEqual(try db.projection(issueID: "1", kind: .mainIssue, generation: 0)?.state, .acknowledged)
        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1020))
        XCTAssertEqual(sink.records.count, 0)
    }

    private func issue(_ status: IssueStatusCategory, run: RunSnapshot? = nil) -> IssueSnapshot {
        IssueSnapshot(
            id: "1", key: "MUL-1", title: "Ask verification",
            statusName: status.rawValue, statusCategory: status,
            projectID: "p1", projectName: "Personal AI",
            latestRun: run
        )
    }

    private func makeDB() throws -> BridgeDatabase {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("bridge-apple-semantics-\(UUID().uuidString).sqlite").path
        let db = try BridgeDatabase(path: path)
        try db.migrate()
        return db
    }
}


private actor FailingStatusSource: MulticaSource {
    let issue: IssueSnapshot
    init(issue: IssueSnapshot) { self.issue = issue }
    func fetchIssues() async throws -> [IssueSnapshot] { [issue] }
    func fetchIssue(idOrKey: String) async throws -> IssueSnapshot { issue }
    func fetchRuns(issueIDOrKey: String) async throws -> [RunSnapshot] { issue.latestRun.map { [$0] } ?? [] }
    func authStatus() async throws -> String { "ok" }
    func version() async throws -> String { "test" }
    func setIssueStatus(issueIDOrKey: String, statusKey: String) async throws {
        throw NSError(domain: "StatusWrite", code: 500)
    }
}
