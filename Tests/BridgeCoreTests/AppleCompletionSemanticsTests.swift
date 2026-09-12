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
        let engine = SyncEngine(source: source, sink: sink, persistence: db, configuration: BridgeConfiguration(projectRoutes: [route], requestDispatchEnabled: false))

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
