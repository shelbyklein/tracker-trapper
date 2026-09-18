import XCTest
@testable import TrackerTrapperCore

final class CompletionNoticeTests: XCTestCase {
    func testCompletionOnlyNotifiesOnTransitions() {
        let before = StoreSnapshot(plans: [Plan(id: "plan", repository: "org/repo", issueNumber: 87, issueURL: "", title: "Plan", todos: [Todo(id: "TT-01", description: "Run tests")])])
        var after = before
        after.plans[0].todos[0].status = .completed
        let notices = CompletionNotice.changes(from: before, to: after)
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(notices.first?.subtitle, "org/repo #87")
        XCTAssertEqual(notices.first?.body, "Run tests")
        XCTAssertTrue(CompletionNotice.changes(from: nil, to: after).isEmpty)
        XCTAssertTrue(CompletionNotice.changes(from: after, to: after).isEmpty)
        XCTAssertTrue(CompletionNotice.changes(from: StoreSnapshot(), to: after).isEmpty)
        after.plans[0].todos[0].status = .skipped
        XCTAssertTrue(CompletionNotice.changes(from: before, to: after).isEmpty)
    }

    func testBatchCompletionGroupsByIssue() {
        let before = StoreSnapshot(plans: [Plan(id: "plan", repository: "org/repo", issueNumber: 1, issueURL: "", title: "Plan", todos: [Todo(id: "a", description: "First"), Todo(id: "b", description: "Second")])])
        var after = before
        after.plans[0].todos[0].status = .completed
        after.plans[0].todos[1].status = .completed
        let notices = CompletionNotice.changes(from: before, to: after)
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(notices.first?.title, "2 todos completed")
        XCTAssertEqual(notices.first?.body, "First\nSecond")
    }

    func testLocalCompletionUsesLocalLabel() {
        let plan = Plan(title: "Local", todos: [Todo(id: "L-1", description: "Finish")], workspacePath: "/tmp/plain", creationRequestKey: "local")
        let before = StoreSnapshot(plans: [plan])
        var after = before; after.plans[0].todos[0].status = .completed
        XCTAssertEqual(CompletionNotice.changes(from: before, to: after).first?.subtitle, "Local")
    }
}
