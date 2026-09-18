import XCTest
@testable import TrackerTrapperCore

final class TrackerStoreTests: XCTestCase {
    func testIndependentStoresReloadAndPreserveBothWriters() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tracker-\(UUID().uuidString)/store.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = try TrackerStore(url: url)
        let second = try TrackerStore(url: url)
        let plan = try await first.register(Plan(repository: "org/repo", issueNumber: 1, issueURL: "", title: "First", todos: [Todo(id: "TT-01", description: "Task")]))
        let visible = try await second.read()
        XCTAssertEqual(visible.plans.first?.id, plan.id)
        _ = try await second.register(Plan(repository: "org/repo", issueNumber: 2, issueURL: "", title: "Second", todos: []))
        let run = try await first.startRun(planID: plan.id, agent: "test", sessionID: "one", repositoryPath: "/tmp")
        try await second.update(runID: run.id, todoID: "TT-01", status: .completed, message: "done", evidence: ["verified"])
        _ = try await first.register(plan)
        let result = try await second.read()
        XCTAssertEqual(result.plans.count, 2)
        XCTAssertEqual(result.plans[0].todos[0].status, .completed)
        XCTAssertEqual(result.plans[0].todos[0].evidence, ["verified"])
    }

    func testCorruptExternalStoreRejectsWritesAndRecovers() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tracker-\(UUID().uuidString)/store.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try TrackerStore(url: url)
        let plan = Plan(repository: "org/repo", issueNumber: 1, issueURL: "", title: "Original", todos: [])
        _ = try await store.register(plan)
        let valid = try Data(contentsOf: url)
        try Data("invalid".utf8).write(to: url)
        do { _ = try await store.read(); XCTFail("Expected read error") } catch {}
        do { _ = try await store.register(plan); XCTFail("Expected write rejection") } catch {}
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "invalid")
        try valid.write(to: url, options: .atomic)
        let recovered = try await store.read()
        XCTAssertEqual(recovered.plans.count, 1)
    }

    func testRegisterIsIdempotentAndPersistsAcrossRestart() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tracker-\(UUID().uuidString).json")
        let plan = Plan(repository: "org/repo", issueNumber: 1, issueURL: "https://github.com/org/repo/issues/1", title: "Test", todos: [Todo(id: "TT-01", description: "First", acceptance: "check")])
        let store = try TrackerStore(url: url); let first = try await store.register(plan); let second = try await store.register(plan)
        XCTAssertEqual(first.id, second.id)
        let stored = try await store.read(); XCTAssertEqual(stored.plans.count, 1)
        let reloaded = try TrackerStore(url: url); let reloadedSnapshot = try await reloaded.read(); XCTAssertEqual(reloadedSnapshot.plans.count, 1)
        try? FileManager.default.removeItem(at: url)
    }

    func testDuplicateEventAndLifecycleKeepEvidenceAndSeparateFreshness() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tracker-\(UUID().uuidString).json")
        let store = try TrackerStore(url: url)
        let plan = try await store.register(Plan(repository: "org/repo", issueNumber: 2, issueURL: "", title: "Test", todos: [Todo(id: "TT-01", description: "First")]))
        let run = try await store.startRun(planID: plan.id, agent: "fixture", sessionID: "session", repositoryPath: "/tmp/worktree")
        try await store.update(runID: run.id, todoID: "TT-01", status: .completed, message: "done", evidence: ["test-output"], eventID: "event-1")
        try await store.update(runID: run.id, todoID: "TT-01", status: .completed, message: "done", evidence: ["test-output"], eventID: "event-1")
        let result = try await store.read(); XCTAssertEqual(result.events.count, 2); XCTAssertEqual(result.plans[0].todos[0].evidence.count, 1)
        XCTAssertNotNil(result.runs[0].lastTaskUpdateAt); XCTAssertGreaterThanOrEqual(result.runs[0].lastActivityAt, result.runs[0].lastTaskUpdateAt!)
        try? FileManager.default.removeItem(at: url)
    }

    func testDifferentWorktreesRemainSeparateRuns() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tracker-\(UUID().uuidString).json")
        let store = try TrackerStore(url: url); let plan = try await store.register(Plan(repository: "org/repo", issueNumber: 3, issueURL: "", title: "Test", todos: []))
        _ = try await store.startRun(planID: plan.id, agent: "a", sessionID: "one", repositoryPath: "/tmp/one")
        _ = try await store.startRun(planID: plan.id, agent: "b", sessionID: "two", repositoryPath: "/tmp/two")
        let runs = try await store.read().runs; XCTAssertEqual(Set(runs.map(\.repositoryPath)), Set(["/tmp/one", "/tmp/two"]))
        try? FileManager.default.removeItem(at: url)
    }

    func testFinishingRunReportsUnresolvedTodos() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tracker-\(UUID().uuidString).json")
        let store = try TrackerStore(url: url)
        let plan = try await store.register(Plan(repository: "org/repo", issueNumber: 4, issueURL: "", title: "Test", todos: [Todo(id: "TT-01", description: "Open")]))
        let run = try await store.startRun(planID: plan.id, agent: "fixture", sessionID: "finish", repositoryPath: "/tmp/finish")
        try await store.finishRun(runID: run.id, status: .finished)
        let event = (try await store.read()).events.last
        XCTAssertEqual(event?.type, "run_finished"); XCTAssertEqual(event?.message, "unresolved todos: TT-01")
        try? FileManager.default.removeItem(at: url)
    }

    func testChangedTodoIDsAreRejectedWithoutMutatingPlan() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tracker-\(UUID().uuidString).json")
        let store = try TrackerStore(url: url)
        let plan = try await store.register(Plan(repository: "org/repo", issueNumber: 5, issueURL: "", title: "Original", todos: [Todo(id: "TT-01", description: "Original")]))
        do { _ = try await store.register(Plan(id: plan.id, repository: "org/repo", issueNumber: 5, issueURL: "", title: "Changed", todos: [Todo(id: "TT-99", description: "Unexpected")])) ; XCTFail("expected conflict") }
        catch let error as StoreError { if case .conflict = error {} else { XCTFail("unexpected error: \(error)") } }
        let current = try await store.read().plans[0]; XCTAssertEqual(current.title, "Original"); XCTAssertEqual(current.todos[0].id, "TT-01")
        try? FileManager.default.removeItem(at: url)
    }

    func testInvalidTodoUpdateDoesNotAddEvent() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tracker-\(UUID().uuidString).json")
        let store = try TrackerStore(url: url)
        let plan = try await store.register(Plan(repository: "org/repo", issueNumber: 6, issueURL: "", title: "Test", todos: []))
        let run = try await store.startRun(planID: plan.id, agent: "fixture", sessionID: "invalid", repositoryPath: "/tmp/invalid")
        do { try await store.update(runID: run.id, todoID: "missing", status: .completed, message: nil); XCTFail("expected not found") }
        catch let error as StoreError { if case .notFound = error {} else { XCTFail("unexpected error: \(error)") } }
        let snapshot = try await store.read(); XCTAssertEqual(snapshot.events.count, 1)
        try? FileManager.default.removeItem(at: url)
    }

    func testRegistrationRetrySurvivesRestartAndClearsAfterRecovery() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tracker-\(UUID().uuidString).json")
        let store = try TrackerStore(url: url)
        let retry = RegistrationRetry(repository: "org/repo", issueNumber: 7, issueURL: "https://github.com/org/repo/issues/7", reason: "temporary import failure")
        try await store.enqueueRegistrationRetry(retry)
        let reloaded = try TrackerStore(url: url)
        let queued = try await reloaded.read()
        XCTAssertEqual(queued.registrationRetries.count, 1)
        XCTAssertEqual(queued.registrationRetries[0].id, retry.id)
        XCTAssertEqual(queued.registrationRetries[0].reason, retry.reason)
        try await reloaded.clearRegistrationRetry(id: retry.id)
        let cleared = try await reloaded.read()
        XCTAssertTrue(cleared.registrationRetries.isEmpty)
        try? FileManager.default.removeItem(at: url)
    }
}
