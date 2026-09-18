import XCTest
@testable import TrackerTrapperCore

final class CompletionCelebrationsTests: XCTestCase {
    func testTodoCompletionQueuesOnceAndCanCelebrateAgainAfterReopening() throws {
        var current = plan([.pending, .pending])
        var queue = CompletionCelebrations()
        queue.observe([current])
        XCTAssertTrue(queue.pendingTodos.isEmpty)

        current.todos[0].status = .completed
        current.todos[0].revision = 1
        queue.observe([current])
        XCTAssertEqual(queue.pendingTodos.map(\.todoID), ["TT-0"])
        XCTAssertEqual(queue.pendingTodos.first?.todoDescription, "Task")
        XCTAssertTrue(queue.pending.isEmpty)

        queue = try JSONDecoder().decode(CompletionCelebrations.self, from: JSONEncoder().encode(queue))
        queue.observe([current])
        XCTAssertEqual(queue.pendingTodos.count, 1)
        queue.acknowledgeTodo(try XCTUnwrap(queue.pendingTodos.first?.id))
        queue.observe([current])
        XCTAssertTrue(queue.pendingTodos.isEmpty)

        current.todos[0].status = .pending
        current.todos[0].revision = 2
        queue.observe([current])
        current.todos[0].status = .completed
        current.todos[0].revision = 3
        queue.observe([current])
        XCTAssertEqual(queue.pendingTodos.count, 1)
    }

    func testFinalCheckboxQueuesTodoBeforeWholePlanCelebration() {
        var current = plan([.completed, .pending])
        var queue = CompletionCelebrations()
        queue.observe([current])
        current.todos[1].status = .completed
        current.todos[1].revision = 1
        queue.observe([current])
        XCTAssertEqual(queue.pendingTodos.map(\.todoID), ["TT-1"])
        XCTAssertEqual(queue.pending.map(\.id), [current.id])
        XCTAssertTrue(queue.hasPendingTodo(for: current.id))
        queue.acknowledgeTodo(queue.pendingTodos[0].id)
        XCTAssertFalse(queue.hasPendingTodo(for: current.id))
        XCTAssertEqual(queue.pending.map(\.id), [current.id])
    }

    func testIssueClosureCelebratesOnceWithoutCompletingTasksAndSurvivesRestart() throws {
        let issue = plan([.pending, .blocked])
        var queue = CompletionCelebrations()
        queue.observe([issue])
        queue.observeGitHubIssue(issue, isClosed: false)
        queue.observeGitHubIssue(issue, isClosed: true)
        queue.observe([issue])
        XCTAssertEqual(queue.pending.map(\.id), [issue.id])
        XCTAssertEqual(queue.pending.first?.todos.map(\.status), [.pending, .blocked])
        queue = try JSONDecoder().decode(CompletionCelebrations.self, from: JSONEncoder().encode(queue))
        queue.observeGitHubIssue(issue, isClosed: true)
        queue.observe([issue])
        XCTAssertEqual(queue.pending.count, 1)
        queue.acknowledge(issue.id)
        queue.observe([issue])
        queue.observeGitHubIssue(issue, isClosed: true)
        XCTAssertTrue(queue.pending.isEmpty)
        XCTAssertTrue(queue.dismissedPlanIDs.contains(issue.id))
        queue.observeGitHubIssue(issue, isClosed: false)
        XCTAssertFalse(queue.dismissedPlanIDs.contains(issue.id))
        queue.observeGitHubIssue(issue, isClosed: true)
        XCTAssertEqual(queue.pending.count, 1)
    }

    func testClosedIssueImportAndClosureAfterChecklistCelebrationDoNotReplay() {
        var issue = plan([.pending])
        var queue = CompletionCelebrations()
        queue.observe([issue])
        queue.observeGitHubIssue(issue, isClosed: true)
        queue.observe([issue])
        XCTAssertTrue(queue.pending.isEmpty)
        queue.observeGitHubIssue(issue, isClosed: false)
        issue.todos[0].status = .completed
        queue.observe([issue])
        XCTAssertEqual(queue.pending.count, 1)
        queue.acknowledge(issue.id)
        queue.observeGitHubIssue(issue, isClosed: true)
        XCTAssertTrue(queue.pending.isEmpty)
    }

    func testLegacyStateDecodesAndReopeningCancelsPendingClosure() throws {
        let data = Data(#"{"pending":[],"dismissedPlanIDs":[],"observedCompletion":{}}"#.utf8)
        var queue = try JSONDecoder().decode(CompletionCelebrations.self, from: data)
        let issue = plan([.pending])
        queue.observeGitHubIssue(issue, isClosed: false)
        queue.observeGitHubIssue(issue, isClosed: true)
        XCTAssertEqual(queue.pending.count, 1)
        queue.observeGitHubIssue(issue, isClosed: false)
        XCTAssertTrue(queue.pending.isEmpty)
        XCTAssertFalse(queue.isClosedIssue(issue.id))
    }

    func testDisabledAnimationAcknowledgesPendingWithoutChangingTasks() {
        var state = CompletionCelebrations()
        var plan = Plan(id: "p", repository: "o/r", issueNumber: 1, issueURL: "", title: "Test", todos: [Todo(id: "t", description: "Task")])
        state.observe([plan])
        plan.todos[0].status = .completed
        state.observe([plan])
        XCTAssertTrue(state.acknowledgeWithoutAnimation())
        XCTAssertTrue(state.pending.isEmpty)
        XCTAssertTrue(state.dismissedPlanIDs.contains("p"))
        XCTAssertFalse(state.acknowledgeWithoutAnimation())
        state.observe([plan])
        XCTAssertTrue(state.pending.isEmpty)
        plan.todos[0].status = .pending
        state.observe([plan])
        XCTAssertFalse(state.dismissedPlanIDs.contains("p"))
    }
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
