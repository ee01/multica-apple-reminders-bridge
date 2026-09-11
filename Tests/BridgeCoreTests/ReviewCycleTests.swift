import XCTest
@testable import BridgeCore

final class ReviewCycleTests: XCTestCase {
    func testFirstObservedReviewStartsAtOne() {
        XCTAssertEqual(ReviewCycleDetector.nextGeneration(previous: nil, current: issue(.inReview)), 1)
    }

    func testStayingInReviewDoesNotIncrement() {
        let previous = IssueObservation(issueID: "1", issueKey: "MUL-1", statusName: "in_review", statusCategory: .inReview, reviewGeneration: 2)
        XCTAssertEqual(ReviewCycleDetector.nextGeneration(previous: previous, current: issue(.inReview)), 2)
    }

    func testReenteringReviewIncrements() {
        let previous = IssueObservation(issueID: "1", issueKey: "MUL-1", statusName: "in_progress", statusCategory: .inProgress, reviewGeneration: 2)
        XCTAssertEqual(ReviewCycleDetector.nextGeneration(previous: previous, current: issue(.inReview)), 3)
    }

    private func issue(_ category: IssueStatusCategory) -> IssueSnapshot {
        IssueSnapshot(id: "1", key: "MUL-1", title: "T", statusName: category.rawValue, statusCategory: category)
    }
}
