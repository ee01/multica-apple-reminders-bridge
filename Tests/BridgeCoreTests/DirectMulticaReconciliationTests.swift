import XCTest
@testable import BridgeCore

@MainActor
final class DirectMulticaReconciliationTests: XCTestCase {
    func testDirectMulticaReworkResolvesReviewSiblingAndNextDeliveryCreatesNewCycle() async throws {
        let route = ProjectRoute(appleListName: "Agent · Personal AI", multicaProjectID: "p1")
        let firstDelivery = issue(status: .inReview, run: RunSnapshot(id: "r0", status: .completed))
        let source = MutableIssueSource(issues: [firstDelivery])
        let sink = InMemoryReminderSink()
        let db = try makeDB()
        try db.upsertBinding(IssueBinding(issueID: "1", issueKey: "MUL-1", origin: .apple, routeID: route.id, projectID: "p1", appleListName: route.appleListName))
        let engine = SyncEngine(source: source, sink: sink, persistence: db, configuration: BridgeConfiguration(projectRoutes: [route], requestDispatchEnabled: false))

        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1000))
        let main = try XCTUnwrap(db.projection(issueID: "1", kind: .mainIssue, generation: 0))
        let review1 = try XCTUnwrap(db.projection(issueID: "1", kind: .humanAction, generation: 1))
        let mainInitialState = try await sink.state(of: main.receipt!, issueKey: "MUL-1", kind: .mainIssue, generation: 0)
        XCTAssertEqual(mainInitialState, .pending)
        let review1InitialState = try await sink.state(of: review1.receipt!, issueKey: "MUL-1", kind: .humanAction, generation: 1)
        XCTAssertEqual(review1InitialState, .pending)

        // User reviews in Multica and asks the agent to rework. Multica can leave the
        // Issue status at in_review while a comment-triggered run becomes active.
        await source.setIssues([issue(status: .inReview, run: RunSnapshot(id: "r1", status: .running))])
        let rework = try await engine.sync(now: Date(timeIntervalSince1970: 1010))
        XCTAssertGreaterThanOrEqual(rework.resolved, 1)
        XCTAssertEqual(try db.projection(issueID: "1", kind: .humanAction, generation: 1)?.state, .resolved)
        let mainDuringReworkState = try await sink.state(of: main.receipt!, issueKey: "MUL-1", kind: .mainIssue, generation: 0)
        XCTAssertEqual(mainDuringReworkState, .pending)

        // Same run finishes while the Issue still says in_review. This must be treated
        // as a fresh review cycle, not as a recreation of the old sibling.
        await source.setIssues([issue(status: .inReview, run: RunSnapshot(id: "r1", status: .completed))])
        let deliveredAgain = try await engine.sync(now: Date(timeIntervalSince1970: 1020))
        XCTAssertEqual(deliveredAgain.humanActionsCreatedOrUpdated, 1)
        XCTAssertEqual(try db.observation(issueID: "1")?.reviewGeneration, 2)
        let review2 = try XCTUnwrap(db.projection(issueID: "1", kind: .humanAction, generation: 2))
        let review2State = try await sink.state(of: review2.receipt!, issueKey: "MUL-1", kind: .humanAction, generation: 2)
        XCTAssertEqual(review2State, .pending)
        XCTAssertNotEqual(review1.receipt?.calendarItemIdentifier, review2.receipt?.calendarItemIdentifier)
    }

    func testDirectMulticaDoneResolvesMainAndOutstandingHumanAction() async throws {
        let route = ProjectRoute(appleListName: "Agent · Personal AI", multicaProjectID: "p1")
        let source = MutableIssueSource(issues: [issue(status: .inReview, run: RunSnapshot(id: "r0", status: .completed))])
        let sink = InMemoryReminderSink()
        let db = try makeDB()
        try db.upsertBinding(IssueBinding(issueID: "1", issueKey: "MUL-1", origin: .apple, routeID: route.id, projectID: "p1", appleListName: route.appleListName))
        let engine = SyncEngine(source: source, sink: sink, persistence: db, configuration: BridgeConfiguration(projectRoutes: [route], requestDispatchEnabled: false))

        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1000))
        let main = try XCTUnwrap(db.projection(issueID: "1", kind: .mainIssue, generation: 0))
        let review = try XCTUnwrap(db.projection(issueID: "1", kind: .humanAction, generation: 1))

        await source.setIssues([issue(status: .done, run: RunSnapshot(id: "r0", status: .completed))])
        let summary = try await engine.sync(now: Date(timeIntervalSince1970: 1010))

        XCTAssertGreaterThanOrEqual(summary.resolved, 2)
        XCTAssertEqual(try db.projection(issueID: "1", kind: .mainIssue, generation: 0)?.state, .resolved)
        XCTAssertEqual(try db.projection(issueID: "1", kind: .humanAction, generation: 1)?.state, .resolved)
        let mainDoneState = try await sink.state(of: main.receipt!, issueKey: "MUL-1", kind: .mainIssue, generation: 0)
        XCTAssertEqual(mainDoneState, .completed)
        let reviewDoneState = try await sink.state(of: review.receipt!, issueKey: "MUL-1", kind: .humanAction, generation: 1)
        XCTAssertEqual(reviewDoneState, .completed)
    }

    func testMulticaOriginDefaultHumanOnlyReviewIsResolvedByDirectRework() async throws {
        let route = ProjectRoute(appleListName: "Agent · Personal AI", multicaProjectID: "p1", mirrorMode: .appleOriginOnly)
        let source = MutableIssueSource(issues: [issue(status: .inReview, run: RunSnapshot(id: "r0", status: .completed))])
        let sink = InMemoryReminderSink()
        let db = try makeDB()
        let engine = SyncEngine(source: source, sink: sink, persistence: db, configuration: BridgeConfiguration(projectRoutes: [route], requestDispatchEnabled: false))

        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1000))
        XCTAssertNil(try db.projection(issueID: "1", kind: .mainIssue, generation: 0))
        let review = try XCTUnwrap(db.projection(issueID: "1", kind: .humanAction, generation: 1))

        await source.setIssues([issue(status: .inReview, run: RunSnapshot(id: "r1", status: .running))])
        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1010))

        XCTAssertEqual(try db.projection(issueID: "1", kind: .humanAction, generation: 1)?.state, .resolved)
        let reviewResolvedState = try await sink.state(of: review.receipt!, issueKey: "MUL-1", kind: .humanAction, generation: 1)
        XCTAssertEqual(reviewResolvedState, .completed)
        XCTAssertNil(try db.projection(issueID: "1", kind: .mainIssue, generation: 0))
    }

    private func issue(status: IssueStatusCategory, run: RunSnapshot?) -> IssueSnapshot {
        IssueSnapshot(
            id: "1", key: "MUL-1", title: "Ask verification",
            statusName: status.rawValue, statusCategory: status,
            projectID: "p1", projectName: "Personal AI",
            updatedAt: Date(timeIntervalSince1970: 900), latestRun: run
        )
    }

    private func makeDB() throws -> BridgeDatabase {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("bridge-direct-reconcile-\(UUID().uuidString).sqlite").path
        let db = try BridgeDatabase(path: path)
        try db.migrate()
        return db
    }
}
