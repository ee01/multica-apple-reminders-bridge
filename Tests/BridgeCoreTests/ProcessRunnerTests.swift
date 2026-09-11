import XCTest
@testable import BridgeCore

final class ProcessRunnerTests: XCTestCase {
    func testCapturesLargeStdoutWithoutPipeDeadlock() async throws {
        let runner = ProcessCommandRunner()
        let size = 512_000
        let result = try await runner.run(
            executable: "/bin/sh",
            arguments: ["-c", "head -c \(size) /dev/zero | tr '\\000' x"],
            timeout: 10
        )
        XCTAssertEqual(result.stdout.utf8.count, size)
        XCTAssertEqual(result.exitCode, 0)
    }

    func testNonZeroExitIncludesStderr() async throws {
        let runner = ProcessCommandRunner()
        do {
            _ = try await runner.run(
                executable: "/bin/sh",
                arguments: ["-c", "printf boom >&2; exit 7"],
                timeout: 10
            )
            XCTFail("Expected failure")
        } catch let error as CommandRunnerError {
            XCTAssertEqual(error, .failed(exitCode: 7, stderr: "boom"))
        }
    }

    func testTimeoutIsReported() async throws {
        let runner = ProcessCommandRunner()
        do {
            _ = try await runner.run(
                executable: "/bin/sh",
                arguments: ["-c", "sleep 3"],
                timeout: 0.2
            )
            XCTFail("Expected timeout")
        } catch let error as CommandRunnerError {
            guard case .timedOut = error else {
                return XCTFail("Expected timeout, got \(error)")
            }
        }
    }
}
