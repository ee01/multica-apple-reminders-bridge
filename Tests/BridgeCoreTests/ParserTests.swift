import XCTest
@testable import BridgeCore

final class ParserTests: XCTestCase {
    func testParsesArrayIssueWithCustomStatusCategory() throws {
        let data = try Data(contentsOf: fixture("issues-array.json"))
        let values = try MulticaJSONParser.parseIssues(data)
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values[0].key, "MUL-123")
        XCTAssertEqual(values[0].statusName, "Code Review")
        XCTAssertEqual(values[0].statusCategory, .inReview)
        XCTAssertEqual(values[0].priority, .high)
        XCTAssertEqual(values[0].assigneeName, "Coding Reviewer")
        XCTAssertEqual(values[0].workspaceSlug, "personal")
    }

    func testParsesWrappedIssuesAndLabels() throws {
        let data = try Data(contentsOf: fixture("issues-wrapped.json"))
        let values = try MulticaJSONParser.parseIssues(data)
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values[0].statusCategory, .blocked)
        XCTAssertEqual(values[0].priority, .urgent)
        XCTAssertTrue(values[0].labels.contains("reminder-urgent"))
    }

    func testParsesAndSortsRunsNewestFirst() throws {
        let data = try Data(contentsOf: fixture("runs.json"))
        let values = try MulticaJSONParser.parseRuns(data)
        XCTAssertEqual(values.count, 2)
        XCTAssertEqual(values[0].id, "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        XCTAssertEqual(values[0].status, .failed)
        XCTAssertEqual(values[0].failureReasonCode, "agent_error")
        XCTAssertNil(values[0].errorMessage)
        XCTAssertEqual(values[0].agentName, "Claude Reviewer")
    }

    func testRejectsInvalidJSON() {
        XCTAssertThrowsError(try MulticaJSONParser.parseIssues(Data("nope".utf8)))
    }

    func testParsesAgentsAndSquadsFromJSONArrays() throws {
        let agents = try MulticaJSONParser.parseAgents(Data(#"[{"id":"a1","name":"Mika"},{"id":"a2","title":"Docs"}]"#.utf8))
        XCTAssertEqual(agents.map(\.id), ["a1", "a2"])
        XCTAssertEqual(agents.map(\.name), ["Mika", "Docs"])
        XCTAssertTrue(agents.allSatisfy { $0.kind == .agent })

        let squads = try MulticaJSONParser.parseSquads(Data(#"{"squads":[{"id":"s1","name":"Personal AI Team"}]}"#.utf8))
        XCTAssertEqual(squads.count, 1)
        XCTAssertEqual(squads[0].id, "s1")
        XCTAssertEqual(squads[0].name, "Personal AI Team")
        XCTAssertEqual(squads[0].kind, .squad)
        XCTAssertEqual(squads[0].menuTitle, "Personal AI Team (Squad)")
    }

    private func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
    }
}
