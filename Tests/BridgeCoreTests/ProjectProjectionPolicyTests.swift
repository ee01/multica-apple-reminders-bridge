import XCTest
@testable import BridgeCore

final class ProjectProjectionPolicyTests: XCTestCase {
    func testDefaultMirrorModeIsAppleOriginOnly() {
        XCTAssertEqual(BridgeConfiguration().defaultMirrorMode, .appleOriginOnly)
    }

    func testAppleOriginGetsMainByDefault() {
        let config = BridgeConfiguration()
        let policy = ProjectProjectionPolicy(configuration: config)
        let issue = makeIssue()
        let binding = IssueBinding(issueID: issue.id, issueKey: issue.key, origin: .apple, appleListName: "Agent Requests")
        let plan = policy.plan(issue: issue, binding: binding)
        XCTAssertTrue(plan.shouldMaintainMain)
        XCTAssertEqual(plan.listName, "Agent Requests")
    }

    func testMulticaOriginDoesNotGetMainByDefault() {
        let policy = ProjectProjectionPolicy(configuration: BridgeConfiguration())
        let plan = policy.plan(issue: makeIssue(), binding: nil)
        XCTAssertFalse(plan.shouldMaintainMain)
    }

    func testAllActiveRouteMirrorsMulticaOriginInProjectList() {
        let route = ProjectRoute(appleListName: "Agent · Personal AI", multicaProjectID: "p1", multicaProjectName: "Personal AI", mirrorMode: .allActive)
        let config = BridgeConfiguration(projectRoutes: [route])
        let policy = ProjectProjectionPolicy(configuration: config)
        let issue = makeIssue(projectID: "p1", projectName: "Personal AI")
        let plan = policy.plan(issue: issue, binding: nil)
        XCTAssertTrue(plan.shouldMaintainMain)
        XCTAssertEqual(plan.listName, "Agent · Personal AI")
    }

    func testAttentionOnlyNeverMaintainsMain() {
        let route = ProjectRoute(appleListName: "Agent · Infra", multicaProjectID: "p2", mirrorMode: .attentionOnly)
        let config = BridgeConfiguration(projectRoutes: [route])
        let binding = IssueBinding(issueID: "1", issueKey: "MUL-1", origin: .apple, routeID: route.id, projectID: "p2", appleListName: route.appleListName)
        let plan = ProjectProjectionPolicy(configuration: config).plan(issue: makeIssue(projectID: "p2"), binding: binding)
        XCTAssertFalse(plan.shouldMaintainMain)
    }

    private func makeIssue(projectID: String? = nil, projectName: String? = nil) -> IssueSnapshot {
        IssueSnapshot(id: "1", key: "MUL-1", title: "Task", statusName: "in_progress", statusCategory: .inProgress, projectID: projectID, projectName: projectName)
    }
}
