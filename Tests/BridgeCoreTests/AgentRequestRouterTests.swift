import XCTest
@testable import BridgeCore

final class AgentRequestRouterTests: XCTestCase {
    func testProjectRouteFallsBackToAgentRequestsAgent() throws {
        let route = ProjectRoute(appleListName: "Personal AI", multicaProjectID: "p1", multicaProjectName: "Personal AI")
        let configuration = BridgeConfiguration(
            genericRequestListName: "Agent Requests",
            projectRoutes: [route],
            defaultAgentID: "inbox-agent",
            defaultAgentName: "Inbox Agent"
        )
        let router = AgentRequestRouter(configuration: configuration)
        let request = AgentRequestSnapshot(
            id: "r1",
            receipt: ReminderReceipt(calendarItemIdentifier: "c1"),
            listName: "personal ai",
            title: "Ship it",
            notes: "",
            url: nil,
            dueDate: nil
        )

        let resolved = try router.route(request)
        XCTAssertEqual(resolved.defaultAgentID, "inbox-agent")
        XCTAssertEqual(resolved.multicaProjectID, "p1")
    }

    func testMissingAgentThrowsWithoutCreatingASilentSkip() {
        let route = ProjectRoute(appleListName: "Personal AI", multicaProjectID: "p1")
        let configuration = BridgeConfiguration(projectRoutes: [route])
        let router = AgentRequestRouter(configuration: configuration)
        let request = AgentRequestSnapshot(
            id: "r1",
            receipt: ReminderReceipt(calendarItemIdentifier: "c1"),
            listName: "Personal AI",
            title: "Ship it",
            notes: "",
            url: nil,
            dueDate: nil
        )

        XCTAssertThrowsError(try router.route(request)) { error in
            XCTAssertEqual(error as? RequestRoutingError, .missingAgent("Personal AI"))
        }
    }
}
