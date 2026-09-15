import XCTest
@testable import BridgeCore

actor DispatchFakeSource: MulticaSource {
    var issues: [IssueSnapshot]
    var comments: [(String, String)] = []
    var createRequests: [IssueCreateRequest] = []
    var assigned: [(String, String)] = []
    var assignedWithoutStarting: [(String, String)] = []

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
    func assignIssueWithoutStarting(issueIDOrKey: String, agentID: String) async throws { assignedWithoutStarting.append((issueIDOrKey, agentID)) }
    func addComment(issueIDOrKey: String, content: String) async throws { comments.append((issueIDOrKey, content)) }

    func createdCount() -> Int { createRequests.count }
    func commentCount() -> Int { comments.count }
    func noStartAssignCount() -> Int { assignedWithoutStarting.count }
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
        XCTAssertEqual(try db.binding(issueID: "1")?.origin, .multica)
        XCTAssertNil(try db.projection(issueID: "1", kind: .mainIssue, generation: 0))
        XCTAssertEqual(sink.records["apple-followup"]?.state, .completed)
    }


    func testContinuationAssignsWithoutStartingBeforeAddingComment() async throws {
        let route = ProjectRoute(appleListName: "Agent · Personal AI", multicaProjectID: "project-1", defaultAgentID: "agent-1")
        let issue = IssueSnapshot(id: "1", key: "MUL-381", title: "Existing", statusName: "todo", statusCategory: .todo, assigneeName: nil, projectID: "project-1", projectName: "Personal AI")
        let source = DispatchFakeSource(issues: [issue])
        let sink = InMemoryReminderSink()
        sink.requests = [AgentRequestSnapshot(
            id: "followup-unassigned",
            receipt: ReminderReceipt(calendarItemIdentifier: "apple-followup-unassigned"),
            listName: route.appleListName,
            title: "Continue existing work",
            notes: "Use the routed agent exactly once",
            url: URL(string: "https://multica.ai/ws/issues/MUL-381"),
            dueDate: nil
        )]
        let db = try makeDB()
        let engine = SyncEngine(source: source, sink: sink, persistence: db, configuration: BridgeConfiguration(projectRoutes: [route]))

        let summary = try await engine.sync(now: Date(timeIntervalSince1970: 1000))

        XCTAssertEqual(summary.continuedRequests, 1)
        let noStartAssignCount = await source.noStartAssignCount()
        let commentCount = await source.commentCount()
        XCTAssertEqual(noStartAssignCount, 1)
        XCTAssertEqual(commentCount, 1)
    }

    func testAttentionOnlyDispatchCompletesRequestWithoutCreatingMain() async throws {
        let route = ProjectRoute(appleListName: "Agent · Background", multicaProjectID: "project-2", defaultAgentID: "agent-2", mirrorMode: .attentionOnly)
        let source = DispatchFakeSource()
        let sink = InMemoryReminderSink()
        sink.requests = [AgentRequestSnapshot(
            id: "attention-only-1",
            receipt: ReminderReceipt(calendarItemIdentifier: "apple-attention-only"),
            listName: route.appleListName,
            title: "Background check",
            notes: "Only alert me if human attention is needed",
            url: nil, dueDate: nil
        )]
        let db = try makeDB()
        let engine = SyncEngine(source: source, sink: sink, persistence: db, configuration: BridgeConfiguration(projectRoutes: [route]))

        let summary = try await engine.sync(now: Date(timeIntervalSince1970: 1000))

        XCTAssertEqual(summary.dispatchedRequests, 1)
        let record = try XCTUnwrap(db.request(requestID: "attention-only-1"))
        let issueID = try XCTUnwrap(record.issueID)
        XCTAssertNil(try db.projection(issueID: issueID, kind: .mainIssue, generation: 0))
        XCTAssertEqual(sink.records["apple-attention-only"]?.state, .completed)
    }


    func testRecoveredAttentionOnlyDispatchDoesNotAccidentallyCreateMain() async throws {
        let route = ProjectRoute(appleListName: "Agent · Background", multicaProjectID: "project-2", defaultAgentID: "agent-2", mirrorMode: .attentionOnly)
        let issue = IssueSnapshot(id: "1", key: "MUL-201", title: "Background check", statusName: "in_progress", statusCategory: .inProgress, assigneeName: "Agent", projectID: "project-2")
        let source = DispatchFakeSource(issues: [issue])
        let sink = InMemoryReminderSink()
        let receipt = ReminderReceipt(calendarItemIdentifier: "recovered-attention-only")
        sink.requests = [AgentRequestSnapshot(id: "req-recovered", receipt: receipt, listName: route.appleListName, title: "Background check", notes: "", url: nil, dueDate: nil)]
        let db = try makeDB()
        try db.upsertRequest(AgentRequestRecord(requestID: "req-recovered", receipt: receipt, sourceListName: route.appleListName, routeID: route.id, issueID: issue.id, issueKey: issue.key, state: .dispatched))
        let engine = SyncEngine(source: source, sink: sink, persistence: db, configuration: BridgeConfiguration(projectRoutes: [route]))

        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1000))

        XCTAssertNil(try db.projection(issueID: issue.id, kind: .mainIssue, generation: 0))
        XCTAssertEqual(sink.records["recovered-attention-only"]?.state, .completed)
        XCTAssertEqual(try db.binding(issueID: issue.id)?.origin, .apple)
    }

    func testRecoveredContinuationPreservesMulticaOriginUnderAppleOriginOnly() async throws {
        let route = ProjectRoute(appleListName: "Agent · Personal AI", multicaProjectID: "project-1", defaultAgentID: "agent-1")
        let issue = IssueSnapshot(id: "1", key: "MUL-381", title: "Existing", statusName: "in_progress", statusCategory: .inProgress, assigneeName: "Coding Agent", projectID: "project-1")
        let source = DispatchFakeSource(issues: [issue])
        let sink = InMemoryReminderSink()
        let receipt = ReminderReceipt(calendarItemIdentifier: "recovered-continuation")
        sink.requests = [AgentRequestSnapshot(id: "req-continue", receipt: receipt, listName: route.appleListName, title: "Continue", notes: "", url: URL(string: "https://multica.ai/ws/issues/MUL-381"), dueDate: nil)]
        let db = try makeDB()
        try db.upsertRequest(AgentRequestRecord(requestID: "req-continue", receipt: receipt, sourceListName: route.appleListName, routeID: route.id, issueID: issue.id, issueKey: issue.key, state: .continued))
        let engine = SyncEngine(source: source, sink: sink, persistence: db, configuration: BridgeConfiguration(projectRoutes: [route]))

        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1000))

        XCTAssertEqual(try db.binding(issueID: issue.id)?.origin, .multica)
        XCTAssertNil(try db.projection(issueID: issue.id, kind: .mainIssue, generation: 0))
        XCTAssertEqual(sink.records["recovered-continuation"]?.state, .completed)
    }

    func testMissingAgentDoesNotCreateIssueAndRecordsError() async throws {
        let route = ProjectRoute(appleListName: "Personal AI", multicaProjectID: "project-1", multicaProjectName: "Personal AI")
        let source = DispatchFakeSource()
        let sink = InMemoryReminderSink()
        sink.requests = [AgentRequestSnapshot(
            id: "no-agent-1",
            receipt: ReminderReceipt(calendarItemIdentifier: "apple-no-agent"),
            listName: route.appleListName,
            title: "Should stay in Reminders",
            notes: "",
            url: nil,
            dueDate: nil
        )]
        let db = try makeDB()
        let engine = SyncEngine(source: source, sink: sink, persistence: db, configuration: BridgeConfiguration(projectRoutes: [route]))

        let summary = try await engine.sync(now: Date(timeIntervalSince1970: 1000))

        XCTAssertEqual(summary.dispatchedRequests, 0)
        XCTAssertEqual(await source.createdCount(), 0)
        XCTAssertTrue(summary.errors.contains(where: { $0.contains("no default Multica agent") }))
        XCTAssertEqual(try db.request(requestID: "no-agent-1")?.state, .failed)
        XCTAssertEqual(sink.records["apple-no-agent"]?.state, .pending)
    }

    private func makeDB() throws -> BridgeDatabase {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("bridge-dispatch-\(UUID().uuidString).sqlite").path
        let db = try BridgeDatabase(path: path)
        try db.migrate()
        return db
    }
}
