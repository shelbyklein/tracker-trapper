import XCTest
@testable import TrackerTrapperCore

final class AttentionNoticeTests: XCTestCase {
    func testImportAndUnchangedStatesAreQuietAndBlockedIdentityIsScoped() {
        let a = Plan(id: "a", repository: "o/a", issueNumber: 1, issueURL: "", title: "A", todos: [Todo(id: "TT-1", description: "First")])
        let b = Plan(id: "b", repository: "o/b", issueNumber: 2, issueURL: "", title: "B", todos: [Todo(id: "TT-1", description: "Second")])
        let before = StoreSnapshot(plans: [a, b])
        var after = before
        after.plans[0].todos[0].status = .blocked
        after.plans[1].todos[0].status = .blocked
        let notices = AttentionNotice.changes(from: before, to: after)
        XCTAssertEqual(Set(notices.map(\.id)).count, 2)
        XCTAssertEqual(notices.map(\.subtitle), ["o/a #1", "o/b #2"])
        XCTAssertTrue(AttentionNotice.changes(from: nil, to: after).isEmpty)
        XCTAssertTrue(AttentionNotice.changes(from: StoreSnapshot(), to: after).isEmpty)
        XCTAssertTrue(AttentionNotice.changes(from: after, to: after).isEmpty)
    }
    func testStaleOnlyAppliesToActiveRunAndClearsWhenActivityReturns() {
        let now = Date(timeIntervalSince1970: 10_000)
        let plan = Plan(id: "p", repository: "o/r", issueNumber: 1, issueURL: "", title: "P", todos: [])
        var run = Run(planID: "p", agent: "Codex", sessionID: "test", repositoryPath: "", lastActivityAt: now.addingTimeInterval(-901))
        XCTAssertTrue(AttentionNotice.current(StoreSnapshot(plans: [plan], runs: [run]), now: now).first?.isStale == true)
        run.status = .finished
        XCTAssertTrue(AttentionNotice.current(StoreSnapshot(plans: [plan], runs: [run]), now: now).isEmpty)
        run.status = .active; run.lastActivityAt = now
        XCTAssertTrue(AttentionNotice.current(StoreSnapshot(plans: [plan], runs: [run]), now: now).isEmpty)
    }
    func testLocalAttentionUsesLocalLabel() {
        var plan = Plan(title: "Local", todos: [Todo(id: "L-1", description: "Blocked")], creationRequestKey: "local")
        plan.todos[0].status = .blocked
        XCTAssertEqual(AttentionNotice.current(StoreSnapshot(plans: [plan])).first?.subtitle, "Local")
    }
}
