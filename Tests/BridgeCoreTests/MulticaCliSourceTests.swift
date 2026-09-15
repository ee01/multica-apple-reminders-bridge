import XCTest
@testable import BridgeCore

actor RecordingRunner: CommandRunning {
    var calls: [[String]] = []
    var timeouts: [TimeInterval] = []
    var handler: @Sendable ([String]) throws -> CommandResult

    init(handler: @escaping @Sendable ([String]) throws -> CommandResult) { self.handler = handler }

    func run(executable: String, arguments: [String], timeout: TimeInterval) async throws -> CommandResult {
        calls.append(arguments)
        timeouts.append(timeout)
        return try handler(arguments)
    }

    func recordedCalls() -> [[String]] { calls }
    func recordedTimeouts() -> [TimeInterval] { timeouts }
}

final class MulticaCliSourceTests: XCTestCase {
    func testLoginNeverStartsDaemon() async throws {
        let runner = RecordingRunner { args in
            return CommandResult(stdout: "ok", stderr: "", exitCode: 0)
        }
        let config = BridgeConfiguration(multicaCLIPath: "/fake/multica", multicaProfile: "reminders-bridge")
        let source = MulticaCliSource(configuration: config, runner: runner)
        try await source.login()
        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls.count, 3)
        XCTAssertTrue(calls[0].starts(with: ["config", "set", "server_url", "https://multica.ai"]))
        XCTAssertTrue(calls[1].starts(with: ["config", "set", "app_url", "https://multica.ai"]))
        XCTAssertTrue(calls[2].starts(with: ["login"]))
        XCTAssertTrue(calls.allSatisfy { !$0.contains("daemon") })
        XCTAssertTrue(calls.allSatisfy { $0.contains("--profile") })
        XCTAssertTrue(calls.allSatisfy { $0.contains("reminders-bridge") })
        XCTAssertTrue(calls.allSatisfy { $0.contains("--server-url") })
        let timeouts = await runner.recordedTimeouts()
        XCTAssertEqual(timeouts, [25, 25, 300])
    }

    func testAuthStatusRejectsUnauthenticatedSuccessOutput() async throws {
        let runner = RecordingRunner { _ in
            CommandResult(stdout: "Not authenticated. Run 'multica login' to authenticate.", stderr: "", exitCode: 0)
        }
        let source = MulticaCliSource(configuration: BridgeConfiguration(), runner: runner)

        do {
            _ = try await source.authStatus()
            XCTFail("Expected unauthenticated status to throw")
        } catch let error as MulticaSourceError {
            guard case .notAuthenticated = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testIssuePaginationAndWorkspaceFlag() async throws {
        let page1 = #"[{"id":"1","key":"MUL-1","title":"A","status":"todo"},{"id":"2","key":"MUL-2","title":"B","status":"todo"}]"#
        let page2 = #"[{"id":"3","key":"MUL-3","title":"C","status":"todo"}]"#
        let runner = RecordingRunner { args in
            let offsetIndex = args.firstIndex(of: "--offset")!
            let offset = args[offsetIndex + 1]
            return CommandResult(stdout: offset == "0" ? page1 : page2, stderr: "", exitCode: 0)
        }
        var config = BridgeConfiguration(multicaCLIPath: "/fake/multica", issuePageSize: 2)
        config.workspaceID = "workspace-1"
        let source = MulticaCliSource(configuration: config, runner: runner)
        let issues = try await source.fetchIssues()
        XCTAssertEqual(issues.count, 3)
        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls.count, 2)
        XCTAssertTrue(calls[0].contains("--workspace-id"))
        XCTAssertTrue(calls[0].contains("workspace-1"))
    }

    func testSetIssueStatusUsesOfficialStatusCommand() async throws {
        let runner = RecordingRunner { args in
            XCTAssertTrue(args.starts(with: ["issue", "status", "MUL-381", "done"]))
            return CommandResult(stdout: "ok", stderr: "", exitCode: 0)
        }
        var config = BridgeConfiguration(multicaCLIPath: "/fake/multica", multicaProfile: "reminders-bridge")
        config.workspaceID = "workspace-1"
        let source = MulticaCliSource(configuration: config, runner: runner)

        try await source.setIssueStatus(issueIDOrKey: "MUL-381", statusKey: "done")

        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertTrue(calls[0].contains("--workspace-id"))
        XCTAssertTrue(calls[0].contains("workspace-1"))
        XCTAssertTrue(calls[0].contains("--profile"))
    }

    func testAssignWithoutStartingUsesNoStartFlag() async throws {
        let runner = RecordingRunner { args in
            XCTAssertTrue(args.starts(with: ["issue", "assign", "MUL-381", "--to-id", "agent-1", "--no-start"]))
            return CommandResult(stdout: "ok", stderr: "", exitCode: 0)
        }
        let config = BridgeConfiguration(multicaCLIPath: "/fake/multica", multicaProfile: "reminders-bridge")
        let source = MulticaCliSource(configuration: config, runner: runner)

        try await source.assignIssueWithoutStarting(issueIDOrKey: "MUL-381", agentID: "agent-1")

        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertTrue(calls[0].contains("--no-start"))
    }

    func testFetchRecentMemberCommentsUsesSummaryAndIgnoresAgentReplies() async throws {
        let json = """
        [
          {"id":"a","author_type":"agent","content":"long agent reply","created_at":"2026-09-14T09:00:00Z"},
          {"id":"b","author_type":"member","content":"bar 会丢失 end date","created_at":"2026-09-14T09:08:00Z"},
          {"id":"c","author_type":"member","content":"怎么样了？","created_at":"2026-09-14T09:13:00Z"}
        ]
        """
        let runner = RecordingRunner { args in
            XCTAssertTrue(args.starts(with: ["issue", "comment", "list", "E-5"]))
            XCTAssertTrue(args.contains("--summary"))
            XCTAssertTrue(args.contains("--compact"))
            return CommandResult(stdout: json, stderr: "", exitCode: 0)
        }
        let source = MulticaCliSource(configuration: BridgeConfiguration(), runner: runner)
        let asks = try await source.fetchRecentMemberComments(issueIDOrKey: "E-5", limit: 2)
        XCTAssertEqual(asks, ["bar 会丢失 end date", "怎么样了？"])
    }

    func testRecoveredCreatedIssueFinishesMissingAssignmentWithoutCreatingDuplicate() async throws {
        let recovered = #"{"id":"1","key":"MUL-1","title":"Recovered","status":"todo"}"#
        let assigned = #"{"id":"1","key":"MUL-1","title":"Recovered","status":"in_progress","assignee":{"name":"Coding Agent"}}"#
        let runner = RecordingRunner { args in
            if args.starts(with: ["issue", "search"]) { return CommandResult(stdout: "[\(recovered)]", stderr: "", exitCode: 0) }
            if args.starts(with: ["issue", "assign"]) { return CommandResult(stdout: "ok", stderr: "", exitCode: 0) }
            if args.starts(with: ["issue", "get"]) { return CommandResult(stdout: assigned, stderr: "", exitCode: 0) }
            XCTFail("Unexpected command: \(args)")
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }
        let config = BridgeConfiguration(multicaCLIPath: "/fake/multica")
        let source = MulticaCliSource(configuration: config, runner: runner)
        let issue = try await source.createIssue(IssueCreateRequest(requestID: "req-1", title: "Recovered", description: "Body", projectID: nil, agentID: "agent-1", dueDate: nil))
        XCTAssertEqual(issue.key, "MUL-1")
        XCTAssertEqual(issue.assigneeName, "Coding Agent")
        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls.filter { $0.starts(with: ["issue", "create"]) }.count, 0)
        XCTAssertEqual(calls.filter { $0.starts(with: ["issue", "assign"]) }.count, 1)
    }

    func testAgentListOmitsTableOnlyFullIDFlag() async throws {
        let runner = RecordingRunner { args in
            XCTAssertTrue(args.starts(with: ["agent", "list"]))
            XCTAssertFalse(args.contains("--full-id"))
            return CommandResult(stdout: #"[{"id":"a1","name":"Mika"}]"#, stderr: "", exitCode: 0)
        }
        var config = BridgeConfiguration(multicaCLIPath: "/fake/multica")
        config.workspaceID = "workspace-1"
        let source = MulticaCliSource(configuration: config, runner: runner)
        let agents = try await source.listAgents()
        XCTAssertEqual(agents.map(\.name), ["Mika"])
        XCTAssertEqual(agents.first?.kind, .agent)
    }

    func testSquadListParsesAssignees() async throws {
        let runner = RecordingRunner { args in
            XCTAssertTrue(args.starts(with: ["squad", "list"]))
            XCTAssertFalse(args.contains("--full-id"))
            return CommandResult(stdout: #"[{"id":"s1","name":"Core Team"}]"#, stderr: "", exitCode: 0)
        }
        var config = BridgeConfiguration(multicaCLIPath: "/fake/multica")
        config.workspaceID = "workspace-1"
        let source = MulticaCliSource(configuration: config, runner: runner)
        let squads = try await source.listSquads()
        XCTAssertEqual(squads.map(\.menuTitle), ["Core Team (Squad)"])
    }

}
