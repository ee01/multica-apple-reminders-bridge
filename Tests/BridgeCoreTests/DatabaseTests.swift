import XCTest
@testable import BridgeCore

final class DatabaseTests: XCTestCase {
    func testPersistsObservationProjectionAndMetaAcrossReopen() throws {
        let path = tempPath()
        do {
            let db = try BridgeDatabase(path: path)
            try db.migrate()
            try db.upsertObservation(IssueObservation(issueID: "1", issueKey: "MUL-1", statusName: "in_review", statusCategory: .inReview, reviewGeneration: 2, payloadHash: "abc"))
            try db.upsertProjection(ReminderProjection(issueID: "1", issueKey: "MUL-1", reviewGeneration: 2, receipt: ReminderReceipt(calendarItemIdentifier: "apple-1"), payloadHash: "abc"))
            try db.setMeta(key: "hello", value: "world")
        }
        do {
            let db = try BridgeDatabase(path: path)
            try db.migrate()
            XCTAssertEqual(try db.observation(issueID: "1")?.reviewGeneration, 2)
            XCTAssertEqual(try db.projection(issueID: "1", reviewGeneration: 2)?.receipt?.calendarItemIdentifier, "apple-1")
            XCTAssertEqual(try db.meta(key: "hello"), "world")
        }
    }

    private func tempPath() -> String {
        FileManager.default.temporaryDirectory.appendingPathComponent("bridge-\(UUID().uuidString).sqlite").path
    }
}
