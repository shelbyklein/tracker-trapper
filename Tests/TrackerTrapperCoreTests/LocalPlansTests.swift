import XCTest
@testable import TrackerTrapperCore

final class LocalPlansTests: XCTestCase {
    private func store() throws -> TrackerStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tracker-local-\(UUID().uuidString).json")
        return try TrackerStore(url: url)
    }

    func testLegacyPlanMigratesAsGitHubAndNewStateDefaultsOff() throws {
        let legacy = """
        {"plans":[{"id":"github:org/repo#1","repository":"org/repo","issueNumber":1,"issueURL":"https://github.com/org/repo/issues/1","title":"Legacy","todos":[],"revision":0,"updatedAt":"2026-09-18T00:00:00Z"}],"runs":[],"events":[],"outbox":[],"registrationRetries":[],"schemaVersion":1}
        """
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(StoreSnapshot.self, from: Data(legacy.utf8))
        XCTAssertEqual(snapshot.plans.first?.source, .github)
        XCTAssertFalse(snapshot.trackingSettings.askAtSessionStart)
        XCTAssertTrue(snapshot.sessionTracking.isEmpty)
    }

    func testMigrationWritesRollbackBackupAndFutureSchemaIsRejected() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tracker-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("store.json")
        let legacy = "{\"plans\":[],\"runs\":[],\"events\":[],\"outbox\":[],\"schemaVersion\":1}"
        try Data(legacy.utf8).write(to: url)
        let store = try TrackerStore(url: url)
        _ = try await store.setTrackingSettings(TrackingSettings(askAtSessionStart: true))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathExtension("schema-1.backup").path))

        let futureURL = directory.appendingPathComponent("future.json")
        try Data("{\"plans\":[],\"runs\":[],\"events\":[],\"outbox\":[],\"schemaVersion\":99}".utf8).write(to: futureURL)
        XCTAssertThrowsError(try TrackerStore(url: futureURL))
    }

    func testLocalRegistrationAndRunAreIdempotentAndStayOutOfGitHubOutbox() async throws {
        let store = try store()
        let todo = Todo(id: "TT-LOCAL-ABC-01", description: "Build local path")
        let first = try await store.registerLocal(title: "Local work", todos: [todo], workspacePath: "/tmp/no-git", creationRequestKey: "codex:session:request")
        let second = try await store.registerLocal(title: "Local work", todos: [todo], workspacePath: "/tmp/no-git", creationRequestKey: "codex:session:request")
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first.source, .local)

        let run = try await store.startRun(planID: first.id, agent: "test", sessionID: "session", repositoryPath: "/tmp/no-git")
        let retry = try await store.startRun(planID: first.id, agent: "test", sessionID: "session", repositoryPath: "/tmp/no-git")
        XCTAssertEqual(run.id, retry.id)
        try await store.update(runID: run.id, todoID: todo.id, status: .completed, message: "done", evidence: ["passed"])
        let snapshot = try await store.read()
        XCTAssertTrue(snapshot.outbox.isEmpty)
        XCTAssertEqual(snapshot.plans.first?.todos.first?.status, .completed)
    }

    func testTwoLocalPlansInSameFolderRemainDistinct() async throws {
        let store = try store()
        let first = try await store.registerLocal(title: "One", todos: [Todo(id: "TT-LOCAL-A-01", description: "One")], workspacePath: "/tmp/work", creationRequestKey: "one")
        let second = try await store.registerLocal(title: "Two", todos: [Todo(id: "TT-LOCAL-B-01", description: "Two")], workspacePath: "/tmp/work", creationRequestKey: "two")
        XCTAssertNotEqual(first.id, second.id)
    }

    func testTrackingSettingsAndSessionDecisionPersist() async throws {
        let store = try store()
        _ = try await store.setTrackingSettings(TrackingSettings(askAtSessionStart: true))
        _ = try await store.setSessionTracking(SessionTracking(client: "codex", sessionID: "session", decision: .declined))
        let snapshot = try await store.read()
        XCTAssertTrue(snapshot.trackingSettings.askAtSessionStart)
        XCTAssertEqual(snapshot.sessionTracking.first?.decision, .declined)
    }

    func testLocalPlanRejectsDuplicateIDsAndGitHubSync() async throws {
        let store = try store()
        do {
            _ = try await store.registerLocal(title: "Bad", todos: [Todo(id: "DUP", description: "One"), Todo(id: "DUP", description: "Two")], workspacePath: nil, creationRequestKey: "bad")
            XCTFail("expected duplicate ID conflict")
        } catch { XCTAssertTrue(error.localizedDescription.contains("duplicate")) }

        let plan = try await store.registerLocal(title: "Local", todos: [Todo(id: "A", description: "Task")], workspacePath: nil, creationRequestKey: "good")
        do {
            try await store.recordSync(planID: plan.id, hash: "hash")
            XCTFail("expected local sync conflict")
        } catch { XCTAssertTrue(error.localizedDescription.contains("cannot be synchronized")) }
    }
}
