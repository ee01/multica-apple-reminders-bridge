import XCTest
@testable import BridgeCore

actor DispatchFakeSource: MulticaSource {
    var issues: [IssueSnapshot]
    var comments: [(String, String)] = []
    var createRequests: [IssueCreateRequest] = []
    var assigned: [(String, String)] = []

    init(issues: [IssueSnapshot] = []) { self.issues = issues }

    func fetchIssues() async throws -> [IssueSnapshot] { issues }
    func fetchIssue(idOrKey: String) async throws -> IssueSnapshot {
        guard let issue = issues.first(where: { $0.id == idOrKey || $0.key == idOrKey }) else { throw NSError(domain: "DispatchFake", code: 404) }
        return issue
    }
    func fetchRuns(issueIDOrKey: String) async throws -> [RunSnapshot] { [] }
    func authStatus() async throws -> String { "ok" }
    func version() async throws -> String { "test" }

    func createIssue(_ request: IssueCreateRequest) async throws -> IssueSnapshot {
        createRequests.append(request)
        if let existing = issues.first(where: { $0.summary?.contains(request.requestID) == true }) { return existing }
        let issue = IssueSnapshot(
            id: "created-\(createRequests.count)", key: "MUL-\(100 + createRequests.count)", title: request.title,
            statusName: "todo", statusCategory: .todo,
            assigneeName: request.agentID == nil ? nil : "Agent",
            projectID: request.projectID, projectName: request.projectID == nil ? nil : "Personal AI",
            dueDate: request.dueDate, summary: "request \(request.requestID)"
        )
        issues.append(issue)
        return issue
    }

    func findIssue(bridgeRequestID: String) async throws -> IssueSnapshot? {
        issues.first(where: { $0.summary?.contains(bridgeRequestID) == true })
    }

    func assignIssue(issueIDOrKey: String, agentID: String) async throws { assigned.append((issueIDOrKey, agentID)) }
    func addComment(issueIDOrKey: String, content: String) async throws { comments.append((issueIDOrKey, content)) }

    func createdCount() -> Int { createRequests.count }
    func commentCount() -> Int { comments.count }
}

@MainActor
final class DispatchAndMainProjectionTests: XCTestCase {
    func testAppleRequestDispatchCreatesIssueAndReusesSameReminderAsMain() async throws {
        let route = ProjectRoute(appleListName: "Agent · Personal AI", multicaProjectID: "project-1", multicaProjectName: "Personal AI", defaultAgentID: "agent-1", defaultAgentName: "Coding Agent")
        let config = BridgeConfiguration(projectRoutes: [route])
        let source = DispatchFakeSource()
        let sink = InMemoryReminderSink()
        let requestReceipt = ReminderReceipt(calendarItemIdentifier: "apple-request-1", externalIdentifier: "icloud-1")
        sink.requests = [AgentRequestSnapshot(id: "icloud-1", receipt: requestReceipt, listName: route.appleListName, title: "Implement feature", notes: "Add tests first", url: nil, dueDate: nil)]
        let db = try makeDB()
        let engine = SyncEngine(source: source, sink: sink, persistence: db, configuration: config)

        let summary = try await engine.sync(now: Date(timeIntervalSince1970: 1000))

        XCTAssertEqual(summary.dispatchedRequests, 1)
        let createdCount = await source.createdCount()
        XCTAssertEqual(createdCount, 1)
        let request = try XCTUnwrap(db.request(requestID: "icloud-1"))
        XCTAssertEqual(request.state, .dispatched)
        let issueID = try XCTUnwrap(request.issueID)
        let binding = try XCTUnwrap(db.binding(issueID: issueID))
        XCTAssertEqual(binding.origin, .apple)
        XCTAssertEqual(binding.appleListName, route.appleListName)
        let main = try XCTUnwrap(db.projection(issueID: issueID, kind: .mainIssue, generation: 0))
        XCTAssertEqual(main.receipt?.calendarItemIdentifier, "apple-request-1")
        XCTAssertEqual(sink.records["apple-request-1"]?.item.kind, .main)
        XCTAssertEqual(sink.records["apple-request-1"]?.item.listName, route.appleListName)
        XCTAssertNil(sink.records["apple-request-1"]?.item.alarmDate)
    }

    func testMulticaOriginDoesNotCreateMainUnderDefaultAppleOriginOnly() async throws {
        let issue = IssueSnapshot(id: "1", key: "MUL-1", title: "Cloud task", statusName: "in_progress", statusCategory: .inProgress)
        let source = DispatchFakeSource(issues: [issue])
        let sink = InMemoryReminderSink()
        let db = try makeDB()
        let engine = SyncEngine(source: source, sink: sink, persistence: db, configuration: BridgeConfiguration(requestDispatchEnabled: false))

        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1000))

        XCTAssertNil(try db.projection(issueID: issue.id, kind: .mainIssue, generation: 0))
        XCTAssertEqual(try db.binding(issueID: issue.id)?.origin, .multica)
    }

    func testIssueURLContinuationAddsCommentInsteadOfCreatingIssue() async throws {
        let route = ProjectRoute(appleListName: "Agent · Personal AI", multicaProjectID: "project-1", defaultAgentID: "agent-1")
        let issue = IssueSnapshot(id: "1", key: "MUL-381", title: "Existing", statusName: "in_progress", statusCategory: .inProgress, assigneeName: "Coding Agent", projectID: "project-1", projectName: "Personal AI")
        let source = DispatchFakeSource(issues: [issue])
        let sink = InMemoryReminderSink()
        sink.requests = [AgentRequestSnapshot(
            id: "followup-1",
            receipt: ReminderReceipt(calendarItemIdentifier: "apple-followup"),
            listName: route.appleListName,
            title: "Add Windows test",
            notes: "Check path handling",
            url: URL(string: "https://multica.ai/ws/issues/MUL-381"),
            dueDate: nil
        )]
        let db = try makeDB()
        let engine = SyncEngine(source: source, sink: sink, persistence: db, configuration: BridgeConfiguration(projectRoutes: [route]))

        let summary = try await engine.sync(now: Date(timeIntervalSince1970: 1000))

        XCTAssertEqual(summary.continuedRequests, 1)
        let createdCount = await source.createdCount()
        let commentCount = await source.commentCount()
        XCTAssertEqual(createdCount, 0)
        XCTAssertEqual(commentCount, 1)
        XCTAssertEqual(try db.binding(issueID: "1")?.origin, .apple)
    }

    private func makeDB() throws -> BridgeDatabase {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("bridge-dispatch-\(UUID().uuidString).sqlite").path
        let db = try BridgeDatabase(path: path)
        try db.migrate()
        return db
    }
}
