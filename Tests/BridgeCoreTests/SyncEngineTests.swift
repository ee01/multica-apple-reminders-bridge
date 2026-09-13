import XCTest
@testable import BridgeCore

actor FakeMulticaSource: MulticaSource {
    var issues: [IssueSnapshot]
    var runs: [String: [RunSnapshot]]

    init(issues: [IssueSnapshot] = [], runs: [String: [RunSnapshot]] = [:]) {
        self.issues = issues
        self.runs = runs
    }

    func setIssues(_ values: [IssueSnapshot]) { issues = values }
    func setRuns(_ values: [RunSnapshot], for key: String) { runs[key] = values }
    func fetchIssues() async throws -> [IssueSnapshot] { issues }
    func fetchIssue(idOrKey: String) async throws -> IssueSnapshot {
        guard let value = issues.first(where: { $0.id == idOrKey || $0.key == idOrKey }) else { throw NSError(domain: "Fake", code: 404) }
        return value
    }
    func fetchRuns(issueIDOrKey: String) async throws -> [RunSnapshot] { runs[issueIDOrKey] ?? [] }
    func authStatus() async throws -> String { "ok" }
    func version() async throws -> String { "test" }
}

@MainActor
final class SyncEngineTests: XCTestCase {
    func testSyncBootstrapsGenericAndProjectRequestLists() async throws {
        let route = ProjectRoute(appleListName: "Agent · Personal AI", multicaProjectID: "p1")
        let source = FakeMulticaSource()
        let sink = InMemoryReminderSink()
        let db = try makeDB()
        let configuration = BridgeConfiguration(genericRequestListName: "Agent Requests", projectRoutes: [route], requestDispatchEnabled: true)
        let engine = SyncEngine(source: source, sink: sink, persistence: db, configuration: configuration)

        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1000))

        XCTAssertEqual(sink.ensuredLists, Set(["Agent Requests", "Agent · Personal AI"]))
    }

    func testFailedSnapshotWithQueuedRetryDoesNotCreateFailedReminder() async throws {
        var listed = issue(.todo)
        listed.latestRun = RunSnapshot(id: "old-failure", status: .failed, failureReasonCode: "runtime_offline")
        let retry = RunSnapshot(id: "new-retry", status: .queued)
        let source = FakeMulticaSource(issues: [listed], runs: ["MUL-1": [retry, listed.latestRun!]])
        let sink = InMemoryReminderSink()
        let db = try makeDB()
        let engine = SyncEngine(source: source, sink: sink, persistence: db, configuration: config())

        let result = try await engine.sync(now: Date(timeIntervalSince1970: 1000))

        XCTAssertEqual(result.humanActionsCreatedOrUpdated, 0)
        XCTAssertNil(try db.projection(issueID: "1", kind: .humanAction, generation: 1))
    }

    func testStaleReviewSnapshotWithActiveReworkRunDoesNotCreateReviewReminder() async throws {
        var listed = issue(.inReview)
        listed.latestRun = RunSnapshot(id: "delivered", status: .completed)
        let active = RunSnapshot(id: "rework", status: .running)
        let source = FakeMulticaSource(issues: [listed], runs: ["MUL-1": [active, listed.latestRun!]])
        let sink = InMemoryReminderSink()
        let db = try makeDB()
        let engine = SyncEngine(source: source, sink: sink, persistence: db, configuration: config())

        let result = try await engine.sync(now: Date(timeIntervalSince1970: 1000))

        XCTAssertEqual(result.humanActionsCreatedOrUpdated, 0)
        XCTAssertNil(try db.projection(issueID: "1", kind: .humanAction, generation: 1))
    }

    func testReviewCreatesOneReminderAndDoesNotDuplicate() async throws {
        let source = FakeMulticaSource(issues: [issue(.inReview)])
        let sink = InMemoryReminderSink()
        let db = try makeDB()
        let engine = SyncEngine(source: source, sink: sink, persistence: db, configuration: config())

        let first = try await engine.sync(now: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(first.createdOrUpdated, 1)
        XCTAssertEqual(sink.records.count, 1)

        let second = try await engine.sync(now: Date(timeIntervalSince1970: 1010))
        XCTAssertEqual(second.createdOrUpdated, 0)
        XCTAssertEqual(sink.records.count, 1)
    }

    func testReviewReworkReviewCreatesNewCycle() async throws {
        let source = FakeMulticaSource(issues: [issue(.inReview)])
        let sink = InMemoryReminderSink()
        let db = try makeDB()
        let engine = SyncEngine(source: source, sink: sink, persistence: db, configuration: config())

        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1000))
        await source.setIssues([issue(.inProgress)])
        let rework = try await engine.sync(now: Date(timeIntervalSince1970: 1010))
        XCTAssertEqual(rework.resolved, 1)

        await source.setIssues([issue(.inReview)])
        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1020))
        XCTAssertEqual(sink.records.count, 2)
        XCTAssertEqual(try db.observation(issueID: "1")?.reviewGeneration, 2)
    }

    func testManualCompletionSuppressesRecreationWithinSameReviewCycle() async throws {
        let source = FakeMulticaSource(issues: [issue(.inReview)])
        let sink = InMemoryReminderSink()
        let db = try makeDB()
        let engine = SyncEngine(source: source, sink: sink, persistence: db, configuration: config())

        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1000))
        let id = try XCTUnwrap(sink.records.keys.first)
        sink.markCompleted(id: id)
        let next = try await engine.sync(now: Date(timeIntervalSince1970: 1010))
        XCTAssertEqual(next.acknowledged, 1)
        XCTAssertEqual(next.createdOrUpdated, 0)
        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1020))
        XCTAssertEqual(sink.records.count, 1)
    }

    func testManualDeleteSuppressesRecreationWithinSameCycle() async throws {
        let source = FakeMulticaSource(issues: [issue(.inReview)])
        let sink = InMemoryReminderSink()
        let db = try makeDB()
        let engine = SyncEngine(source: source, sink: sink, persistence: db, configuration: config())
        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1000))
        let id = try XCTUnwrap(sink.records.keys.first)
        sink.delete(id: id)
        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1010))
        XCTAssertEqual(sink.records.count, 0)
        XCTAssertEqual(try db.projection(issueID: "1", reviewGeneration: 1)?.state, .dismissed)
    }

    func testDoneCompletesActiveReminder() async throws {
        let source = FakeMulticaSource(issues: [issue(.inReview)])
        let sink = InMemoryReminderSink()
        let db = try makeDB()
        let engine = SyncEngine(source: source, sink: sink, persistence: db, configuration: config())
        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1000))
        await source.setIssues([issue(.done)])
        let summary = try await engine.sync(now: Date(timeIntervalSince1970: 1010))
        XCTAssertEqual(summary.resolved, 1)
        XCTAssertEqual(try db.projection(issueID: "1", reviewGeneration: 1)?.state, .resolved)
    }

    func testBlockedGraceAndFailureHydration() async throws {
        var c = config(); c.blockedGraceSeconds = 10
        let blocked = issue(.blocked)
        let source = FakeMulticaSource(issues: [blocked])
        let sink = InMemoryReminderSink()
        let db = try makeDB()
        let engine = SyncEngine(source: source, sink: sink, persistence: db, configuration: c)
        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(sink.records.count, 0)
        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1011))
        XCTAssertEqual(sink.records.count, 1)
    }

    func testFailedTodoRunCreatesReminder() async throws {
        let todo = issue(.todo)
        let source = FakeMulticaSource(issues: [todo], runs: ["MUL-1": [RunSnapshot(id: "r1", status: .failed)]])
        let sink = InMemoryReminderSink()
        let db = try makeDB()
        let engine = SyncEngine(source: source, sink: sink, persistence: db, configuration: config())
        let summary = try await engine.sync(now: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(summary.createdOrUpdated, 1)
        XCTAssertEqual(sink.records.count, 1)
    }

    private func issue(_ category: IssueStatusCategory) -> IssueSnapshot {
        IssueSnapshot(id: "1", key: "MUL-1", title: "Test issue", statusName: category.rawValue, statusCategory: category, updatedAt: Date(timeIntervalSince1970: 900), summary: "Short result")
    }

    private func config() -> BridgeConfiguration {
        BridgeConfiguration(workspaceSlug: "personal", issuePageSize: 100, maxRunHydrationPerSync: 30, blockedGraceSeconds: 600, reviewCompletionBehavior: .acknowledgeOnly)
    }

    private func makeDB() throws -> BridgeDatabase {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("bridge-test-\(UUID().uuidString).sqlite").path
        let db = try BridgeDatabase(path: path)
        try db.migrate()
        return db
    }
}

actor SplitListAndDetailSource: MulticaSource {
    var listed: [IssueSnapshot]
    var details: [String: IssueSnapshot]

    init(listed: [IssueSnapshot], details: [String: IssueSnapshot]) {
        self.listed = listed
        self.details = details
    }

    func fetchIssues() async throws -> [IssueSnapshot] { listed }
    func fetchIssue(idOrKey: String) async throws -> IssueSnapshot {
        guard let value = details[idOrKey] else { throw NSError(domain: "SplitFake", code: 404) }
        return value
    }
    func fetchRuns(issueIDOrKey: String) async throws -> [RunSnapshot] { [] }
    func authStatus() async throws -> String { "ok" }
    func version() async throws -> String { "test" }
}

@MainActor
final class SyncEngineClosedListRecoveryTests: XCTestCase {
    func testActiveProjectionIsResolvedWhenClosedIssueDropsOutOfList() async throws {
        let initial = IssueSnapshot(
            id: "1", key: "MUL-1", title: "Review me",
            statusName: "in_review", statusCategory: .inReview,
            updatedAt: Date(timeIntervalSince1970: 900)
        )
        let done = IssueSnapshot(
            id: "1", key: "MUL-1", title: "Review me",
            statusName: "done", statusCategory: .done,
            updatedAt: Date(timeIntervalSince1970: 1100)
        )
        let source = SplitListAndDetailSource(listed: [initial], details: ["MUL-1": done])
        let sink = InMemoryReminderSink()
        let db = try makeDB()
        let configuration = BridgeConfiguration(workspaceSlug: "personal")
        let engine = SyncEngine(source: source, sink: sink, persistence: db, configuration: configuration)

        _ = try await engine.sync(now: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(sink.records.count, 1)

        await source.setListed([])
        let summary = try await engine.sync(now: Date(timeIntervalSince1970: 1200))

        XCTAssertEqual(summary.resolved, 1)
        XCTAssertEqual(try db.projection(issueID: "1", reviewGeneration: 1)?.state, .resolved)
    }

    private func makeDB() throws -> BridgeDatabase {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("bridge-closed-test-\(UUID().uuidString).sqlite").path
        let db = try BridgeDatabase(path: path)
        try db.migrate()
        return db
    }
}

private extension SplitListAndDetailSource {
    func setListed(_ issues: [IssueSnapshot]) { listed = issues }
}
