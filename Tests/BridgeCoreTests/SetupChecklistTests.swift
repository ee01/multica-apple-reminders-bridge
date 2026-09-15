import XCTest
@testable import BridgeCore

final class SetupChecklistTests: XCTestCase {
    func testNextStepSkipsAssigneeBecauseADefaultIsChosenAutomatically() {
        var checklist = SetupChecklist(isAuthenticated: false, hasWorkspace: false, hasRemindersAccess: false)
        XCTAssertEqual(checklist.nextStep, .connect)
        XCTAssertFalse(checklist.isReadyToSync)

        checklist.isAuthenticated = true
        XCTAssertEqual(checklist.nextStep, .workspace)

        checklist.hasWorkspace = true
        XCTAssertEqual(checklist.nextStep, .reminders)

        checklist.hasRemindersAccess = true
        XCTAssertEqual(checklist.nextStep, .done)
        XCTAssertTrue(checklist.isReadyToSync)
        XCTAssertTrue(checklist.isComplete)
    }

    func testPreferredDefaultAssigneePrefersMikaThenFirstAgent() {
        let memory = MulticaAgent(id: "1", name: "Memory Service Engineer")
        let mika = MulticaAgent(id: "2", name: "Mika")
        let squad = MulticaAgent(id: "3", name: "Core Team", kind: .squad)
        XCTAssertEqual([memory, mika, squad].preferredDefaultAssignee()?.id, "2")
        XCTAssertEqual([memory, squad].preferredDefaultAssignee()?.id, "1")
        XCTAssertEqual([squad].preferredDefaultAssignee()?.id, "3")
        XCTAssertNil([MulticaAgent]().preferredDefaultAssignee())
    }

    func testMirrorModeNamesDescribeBehaviorNotInternalKeys() {
        XCTAssertEqual(MirrorMode.appleOriginOnly.displayName, "Only tasks started in Reminders")
        XCTAssertFalse(MirrorMode.appleOriginOnly.displayName.localizedCaseInsensitiveContains("origin"))
        XCTAssertTrue(MirrorMode.appleOriginOnly.helpText.contains("Multica"))
    }
}
