import XCTest
@testable import TrackerTrapperCore

final class TrackerStoreTests: XCTestCase {
    func testRegisterIsIdempotentAndPersistsAcrossRestart() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tracker-\(UUID().uuidString).json")
        let plan = Plan(repository: "org/repo", issueNumber: 1, issueURL: "https://github.com/org/repo/issues/1", title: "Test", todos: [Todo(id: "TT-01", description: "First", acceptance: "check")])
        let store = try TrackerStore(url: url); let first = try await store.register(plan); let second = try await store.register(plan)
        XCTAssertEqual(first.id, second.id)
        let stored = await store.read(); XCTAssertEqual(stored.plans.count, 1)
        let reloaded = try TrackerStore(url: url); let reloadedSnapshot = await reloaded.read(); XCTAssertEqual(reloadedSnapshot.plans.count, 1)
        try? FileManager.default.removeItem(at: url)
    }

    func testDuplicateEventAndLifecycleKeepEvidenceAndSeparateFreshness() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tracker-\(UUID().uuidString).json")
        let store = try TrackerStore(url: url)
        let plan = try await store.register(Plan(repository: "org/repo", issueNumber: 2, issueURL: "", title: "Test", todos: [Todo(id: "TT-01", description: "First")]))
        let run = try await store.startRun(planID: plan.id, agent: "fixture", sessionID: "session", repositoryPath: "/tmp/worktree")
        try await store.update(runID: run.id, todoID: "TT-01", status: .completed, message: "done", evidence: ["test-output"], eventID: "event-1")
        try await store.update(runID: run.id, todoID: "TT-01", status: .completed, message: "done", evidence: ["test-output"], eventID: "event-1")
        let result = await store.read(); XCTAssertEqual(result.events.count, 2); XCTAssertEqual(result.plans[0].todos[0].evidence.count, 1)
        XCTAssertNotNil(result.runs[0].lastTaskUpdateAt); XCTAssertGreaterThanOrEqual(result.runs[0].lastActivityAt, result.runs[0].lastTaskUpdateAt!)
        try? FileManager.default.removeItem(at: url)
    }

    func testDifferentWorktreesRemainSeparateRuns() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tracker-\(UUID().uuidString).json")
        let store = try TrackerStore(url: url); let plan = try await store.register(Plan(repository: "org/repo", issueNumber: 3, issueURL: "", title: "Test", todos: []))
        _ = try await store.startRun(planID: plan.id, agent: "a", sessionID: "one", repositoryPath: "/tmp/one")
        _ = try await store.startRun(planID: plan.id, agent: "b", sessionID: "two", repositoryPath: "/tmp/two")
        let runs = await store.read().runs; XCTAssertEqual(Set(runs.map(\.repositoryPath)), Set(["/tmp/one", "/tmp/two"]))
        try? FileManager.default.removeItem(at: url)
    }

    func testFinishingRunReportsUnresolvedTodos() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tracker-\(UUID().uuidString).json")
        let store = try TrackerStore(url: url)
        let plan = try await store.register(Plan(repository: "org/repo", issueNumber: 4, issueURL: "", title: "Test", todos: [Todo(id: "TT-01", description: "Open")]))
        let run = try await store.startRun(planID: plan.id, agent: "fixture", sessionID: "finish", repositoryPath: "/tmp/finish")
        try await store.finishRun(runID: run.id, status: .finished)
        let event = (await store.read()).events.last
        XCTAssertEqual(event?.type, "run_finished"); XCTAssertEqual(event?.message, "unresolved todos: TT-01")
        try? FileManager.default.removeItem(at: url)
    }
}
