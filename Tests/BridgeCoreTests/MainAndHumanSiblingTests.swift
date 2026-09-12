import XCTest
@testable import BridgeCore

@MainActor
final class MainAndHumanSiblingTests: XCTestCase {
    func testAppleOriginReviewKeepsMainAndCreatesSiblingInSameProjectList() async throws {
        let route = ProjectRoute(appleListName: "Agent · Personal AI", multicaProjectID: "p1", defaultAgentID: "agent-1")
        let issue = IssueSnapshot(id: "1", key: "MUL-1", title: "Ask skip", statusName: "in_review", statusCategory: .inReview, projectID: "p1", projectName: "Personal AI", summary: "Ready for review")
        let source = MutableIssueSource(issues: [issue])
        let sink = InMemoryReminderSink()
        let db = try makeDB()
        try db.upsertBinding(IssueBinding(issueID: "1", issueKey: "MUL-1", origin: .apple, routeID: route.id, projectID: "p1", projectName: "Personal AI", appleListName: route.appleListName))
        let engine = SyncEngine(source: source, sink: sink, persistence: db, configuration: BridgeConfiguration(projectRoutes: [route], requestDispatchEnabled: false, reminderAlarmDelaySeconds: 60))
        let now = Date(timeIntervalSince1970: 1000)

        let summary = try await engine.sync(now: now)

        XCTAssertEqual(summary.mainCreatedOrUpdated, 1)
        XCTAssertEqual(summary.humanActionsCreatedOrUpdated, 1)
        let main = try XCTUnwrap(db.projection(issueID: "1", kind: .mainIssue, generation: 0))
        let action = try XCTUnwrap(db.projection(issueID: "1", kind: .humanAction, generation: 1))
        XCTAssertEqual(main.listName, route.appleListName)
        XCTAssertEqual(action.listName, route.appleListName)
        XCTAssertEqual(action.humanActionKind, .review)
        let mainItem = try XCTUnwrap(main.receipt?.calendarItemIdentifier.flatMap { sink.records[$0]?.item })
        let actionItem = try XCTUnwrap(action.receipt?.calendarItemIdentifier.flatMap { sink.records[$0]?.item })
        XCTAssertEqual(mainItem.kind, .main)
        XCTAssertNil(mainItem.alarmDate)
        XCTAssertEqual(actionItem.kind, .humanAction)
        XCTAssertEqual(actionItem.alarmDate, now.addingTimeInterval(60))
    }

    func testMulticaOriginReviewCreatesOnlyHumanSiblingByDefault() async throws {
        let route = ProjectRoute(appleListName: "Agent · Personal AI", multicaProjectID: "p1", mirrorMode: .appleOriginOnly)
        let issue = IssueSnapshot(id: "1", key: "MUL-1", title: "Cloud task", statusName: "in_review", statusCategory: .inReview, projectID: "p1", projectName: "Personal AI")
        let source = MutableIssueSource(issues: [issue])
        let sink = InMemoryReminderSink()
        let db = try makeDB()
        let engine = SyncEngine(source: source, sink: sink, persistence: db, configuration: BridgeConfiguration(projectRoutes: [route], requestDispatchEnabled: false))

        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1000))

        XCTAssertNil(try db.projection(issueID: "1", kind: .mainIssue, generation: 0))
        let human = try XCTUnwrap(db.projection(issueID: "1", kind: .humanAction, generation: 1))
        XCTAssertEqual(human.listName, route.appleListName)
        XCTAssertEqual(sink.records.count, 1)
    }

    func testAllActiveMulticaOriginCreatesMainAndHumanSibling() async throws {
        let route = ProjectRoute(appleListName: "Agent · Infra", multicaProjectID: "p2", mirrorMode: .allActive)
        let issue = IssueSnapshot(id: "2", key: "MUL-2", title: "Deploy", statusName: "in_review", statusCategory: .inReview, projectID: "p2")
        let source = MutableIssueSource(issues: [issue])
        let sink = InMemoryReminderSink()
        let db = try makeDB()
        let engine = SyncEngine(source: source, sink: sink, persistence: db, configuration: BridgeConfiguration(projectRoutes: [route], requestDispatchEnabled: false))

        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1000))

        XCTAssertNotNil(try db.projection(issueID: "2", kind: .mainIssue, generation: 0))
        XCTAssertNotNil(try db.projection(issueID: "2", kind: .humanAction, generation: 1))
        XCTAssertEqual(sink.records.count, 2)
    }

    func testBlockedCreatesUnblockSiblingAfterGrace() async throws {
        let route = ProjectRoute(appleListName: "Agent · Personal AI", multicaProjectID: "p1")
        let issue = IssueSnapshot(id: "1", key: "MUL-1", title: "Need input", statusName: "blocked", statusCategory: .blocked, projectID: "p1")
        let source = MutableIssueSource(issues: [issue])
        let sink = InMemoryReminderSink()
        let db = try makeDB()
        let config = BridgeConfiguration(projectRoutes: [route], requestDispatchEnabled: false, blockedGraceSeconds: 10)
        let engine = SyncEngine(source: source, sink: sink, persistence: db, configuration: config)

        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1000))
        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1011))

        let human = try XCTUnwrap(db.projection(issueID: "1", kind: .humanAction, generation: 1))
        XCTAssertEqual(human.humanActionKind, .unblock)
        XCTAssertTrue(sink.records[human.receipt!.calendarItemIdentifier!]!.item.title.hasPrefix("Unblock:"))
    }

    private func makeDB() throws -> BridgeDatabase {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("bridge-sibling-\(UUID().uuidString).sqlite").path
        let db = try BridgeDatabase(path: path); try db.migrate(); return db
    }
}

actor MutableIssueSource: MulticaSource {
    var issues: [IssueSnapshot]
    var runs: [String: [RunSnapshot]]
    init(issues: [IssueSnapshot], runs: [String: [RunSnapshot]] = [:]) { self.issues = issues; self.runs = runs }
    func setIssues(_ values: [IssueSnapshot]) { issues = values }
    func setRuns(_ values: [RunSnapshot], for key: String) { runs[key] = values }
    func fetchIssues() async throws -> [IssueSnapshot] { issues }
    func fetchIssue(idOrKey: String) async throws -> IssueSnapshot { try XCTUnwrap(issues.first(where: { $0.id == idOrKey || $0.key == idOrKey })) }
    func fetchRuns(issueIDOrKey: String) async throws -> [RunSnapshot] { runs[issueIDOrKey] ?? [] }
    func authStatus() async throws -> String { "ok" }
    func version() async throws -> String { "test" }
}
