import XCTest
@testable import TrackerTrapperCore

final class CompletionCelebrationsTests: XCTestCase {
    private func plan(_ statuses: [TodoStatus]) -> Plan {
        Plan(id: "issue", repository: "org/project", issueNumber: 1, issueURL: "", title: "Test", todos: statuses.enumerated().map { Todo(id: "TT-\($0.offset)", description: "Task", status: $0.element) })
    }

    func testCompletionWaitsForAllTasksAndPersistsUntilAcknowledged() throws {
        var queue = CompletionCelebrations()
        queue.observe([plan([.pending, .pending])])
        queue.observe([plan([.completed, .pending])])
        XCTAssertTrue(queue.pending.isEmpty)
        queue.observe([plan([.completed, .completed])])
        XCTAssertEqual(queue.pending.map(\.id), ["issue"])
        queue = try JSONDecoder().decode(CompletionCelebrations.self, from: JSONEncoder().encode(queue))
        queue.observe([plan([.completed, .completed])])
        XCTAssertEqual(queue.pending.count, 1)
        queue.acknowledge("issue")
        queue.observe([plan([.completed, .completed])])
        XCTAssertTrue(queue.pending.isEmpty)
        XCTAssertTrue(queue.dismissedPlanIDs.contains("issue"))
        queue.observe([plan([.completed, .pending])])
        XCTAssertFalse(queue.dismissedPlanIDs.contains("issue"))
        queue.observe([plan([.completed, .completed])])
        XCTAssertEqual(queue.pending.count, 1)
    }

    func testImportsSkippedOnlyAndRemovedIssuesDoNotCelebrate() {
        var queue = CompletionCelebrations()
        queue.observe([plan([.completed])])
        XCTAssertTrue(queue.pending.isEmpty)
        queue.observe([plan([.pending])])
        queue.observe([plan([.skipped])])
        XCTAssertTrue(queue.pending.isEmpty)
        queue.observe([plan([.pending])])
        queue.observe([plan([.completed])])
        XCTAssertEqual(queue.pending.count, 1)
        queue.observe([])
        XCTAssertTrue(queue.pending.isEmpty)
    }
}
