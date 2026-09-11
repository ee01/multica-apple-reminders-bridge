import XCTest
@testable import BridgeCore

actor RecordingRunner: CommandRunning {
    var calls: [[String]] = []
    var handler: @Sendable ([String]) throws -> CommandResult

    init(handler: @escaping @Sendable ([String]) throws -> CommandResult) { self.handler = handler }

    func run(executable: String, arguments: [String], timeout: TimeInterval) async throws -> CommandResult {
        calls.append(arguments)
        return try handler(arguments)
    }

    func recordedCalls() -> [[String]] { calls }
}

final class MulticaCliSourceTests: XCTestCase {
    func testLoginNeverStartsDaemon() async throws {
        let runner = RecordingRunner { args in
            XCTAssertTrue(args.contains("login"))
            return CommandResult(stdout: "ok", stderr: "", exitCode: 0)
        }
        let config = BridgeConfiguration(multicaCLIPath: "/fake/multica", multicaProfile: "reminders-bridge")
        let source = MulticaCliSource(configuration: config, runner: runner)
        try await source.login()
        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertFalse(calls[0].contains("daemon"))
        XCTAssertTrue(calls[0].contains("--profile"))
        XCTAssertTrue(calls[0].contains("reminders-bridge"))
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
}
