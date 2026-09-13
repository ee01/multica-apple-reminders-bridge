import XCTest
@testable import BridgeCore

final class ConfigurationTests: XCTestCase {
    func testOlderConfigurationWithoutAlarmFieldsGetsSafeDefaults() throws {
        let json = #"{"multicaCLIPath":"/usr/local/bin/multica","multicaProfile":"bridge","appBaseURL":"https://multica.ai","reminderListName":"Reviews","pollIntervalSeconds":120,"issuePageSize":50,"maxRunHydrationPerSync":10,"blockedGraceSeconds":300,"failureRemindersEnabled":true,"suppressionLabels":["no-reminder"],"urgentLabels":[],"alwaysLabels":[]}"#
        let config = try JSONDecoder().decode(BridgeConfiguration.self, from: Data(json.utf8))
        XCTAssertEqual(config.multicaProfile, "bridge")
        XCTAssertTrue(config.reminderAlarmEnabled)
        XCTAssertEqual(config.reminderAlarmDelaySeconds, 60)
        XCTAssertEqual(config.defaultMirrorMode, .appleOriginOnly)
        XCTAssertEqual(config.reviewCompletionBehavior, .closeIssue)
    }
}
