import XCTest
@testable import TrackerTrapperCore

final class NextTaskTests: XCTestCase {
    func testNextTaskPersistsAndCompletionAtomicallyAdvancesIt() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("next-\(UUID().uuidString)/store.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try TrackerStore(url: url)
        let plan = try await store.register(Plan(repository: "test/repo", issueNumber: 1, issueURL: "", title: "Test", todos: [Todo(id: "A", description: "First"), Todo(id: "B", description: "Second")]))
        let run = try await store.startRun(planID: plan.id, agent: "test", sessionID: "test", repositoryPath: "/tmp")
        try await store.update(runID: run.id, todoID: nil, status: nil, message: nil, nextTodoID: "A")
        // Simulate an older client rewriting known fields and dropping the new one.
        var legacy = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        var legacyPlans = legacy["plans"] as! [[String: Any]]
        legacyPlans[0].removeValue(forKey: "nextTodoID")
        legacy["plans"] = legacyPlans
        try JSONSerialization.data(withJSONObject: legacy).write(to: url)
        _ = try await store.register(plan)
        let reopened = try TrackerStore(url: url)
        var saved = try await reopened.read()
        XCTAssertEqual(saved.plans[0].nextTodo?.id, "A")
        try await store.update(runID: run.id, todoID: "A", status: .completed, message: nil, eventID: "advance", nextTodoID: "B")
        // A duplicate event must not restore an older next selection.
        try await store.update(runID: run.id, todoID: "A", status: .completed, message: nil, eventID: "advance", nextTodoID: "A")
        saved = try await reopened.read()
        XCTAssertEqual(saved.plans[0].nextTodo?.id, "B")
        XCTAssertEqual(saved.plans[0].todos[0].status, .completed)
        try await store.update(runID: run.id, todoID: "B", status: .skipped, message: nil)
        saved = try await reopened.read()
        XCTAssertNil(saved.plans[0].nextTodoID)
    }

    func testInvalidNextTaskRollsBackWholeUpdateAndClearIsExplicit() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("next-\(UUID().uuidString)/store.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try TrackerStore(url: url)
        let plan = try await store.register(Plan(repository: "test/repo", issueNumber: 1, issueURL: "", title: "Test", todos: [Todo(id: "A", description: "First")]))
        let run = try await store.startRun(planID: plan.id, agent: "test", sessionID: "test", repositoryPath: "/tmp")
        try await store.update(runID: run.id, todoID: nil, status: nil, message: nil, nextTodoID: "A")
        let before = try await store.read()
        for invalid in ["missing", "A"] {
            do {
                try await store.update(runID: run.id, todoID: "A", status: .completed, message: nil, nextTodoID: invalid)
                XCTFail("Expected invalid next task rejection")
            } catch {}
            let after = try await store.read()
            XCTAssertEqual(after, before)
        }
        try await store.update(runID: run.id, todoID: nil, status: nil, message: "activity")
        var saved = try await store.read()
        XCTAssertEqual(saved.plans[0].nextTodoID, "A")
        try await store.update(runID: run.id, todoID: nil, status: nil, message: nil, nextTodoID: "")
        saved = try await store.read()
        XCTAssertNil(saved.plans[0].nextTodoID)
    }

    func testOlderPlansDecodeWithoutNextTask() throws {
        let plan = Plan(repository: "test/repo", issueNumber: 1, issueURL: "", title: "Old", todos: [])
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(plan)) as! [String: Any]
        json.removeValue(forKey: "nextTodoID")
        let decoded = try JSONDecoder().decode(Plan.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.nextTodoID)
    }
}
