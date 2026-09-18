import XCTest
@testable import TrackerTrapperCore

final class SessionWatcherTests: XCTestCase {
    private func fixture() throws -> (URL, URL, TrackerStore) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("watch-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let log = directory.appendingPathComponent("session.jsonl")
        try line(["type": "session_meta", "payload": ["id": "session-one"]]).write(to: log)
        return (directory, log, try TrackerStore(url: directory.appendingPathComponent("store.json")))
    }
    private func line(_ value: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: value); data.append(10); return data
    }
    private func append(_ value: [String: Any], to url: URL) throws {
        let file = try FileHandle(forWritingTo: url); defer { try? file.close() }
        try file.seekToEnd(); try file.write(contentsOf: line(value))
    }
    private func message(_ text: String, role: String = "assistant", date: Date = .now) -> [String: Any] {
        ["timestamp": ISO8601DateFormatter().string(from: date), "type": "response_item", "payload": ["type": "message", "role": role, "content": [["type": "output_text", "text": text]]]]
    }
    private func run(_ store: TrackerStore) async throws -> Run {
        let plan = try await store.register(Plan(repository: "test/repo", issueNumber: 87, issueURL: "", title: "Watcher test", todos: [Todo(id: "TT-87-01", description: "First"), Todo(id: "TT-87-02", description: "Second")]))
        return try await store.startRun(planID: plan.id, agent: "test", sessionID: "session-one", repositoryPath: "/tmp")
    }

    func testNewActivityCompletionAndDurableCursor() async throws {
        let (directory, log, store) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let run = try await run(store)
        try append(message("- [x] TT-87-02 — old completion must not replay"), to: log)
        let watcher = SessionWatcher(store: store)
        _ = try await watcher.link(runID: run.id, sourcePath: log.path, format: .codex)
        _ = try await watcher.poll()
        let baseline = try await store.read()
        XCTAssertEqual(baseline.plans[0].todos[1].status, .pending)
        try append(message("Running tests"), to: log)
        _ = try await watcher.poll()
        let activity = try await store.read()
        XCTAssertNil(activity.runs[0].lastTaskUpdateAt)
        XCTAssertEqual(activity.events.last?.message, "Running tests")
        try append(message("- [x] TT-87-01 — unit tests passed"), to: log)
        _ = try await watcher.poll()
        let completed = try await store.read()
        XCTAssertEqual(completed.plans[0].todos[0].status, .completed)
        XCTAssertEqual(completed.plans[0].todos[1].status, .pending)
        XCTAssertTrue(completed.plans[0].todos[0].evidence[0].contains("Agent-reported"))
        let restarted = SessionWatcher(store: store)
        _ = try await restarted.poll()
        _ = try await restarted.link(runID: run.id, sourcePath: log.path, format: .codex)
        _ = try await restarted.poll()
        let unchanged = try await store.read()
        XCTAssertEqual(unchanged, completed)
    }

    func testPartialLinesNoiseAndTruncation() async throws {
        let (directory, log, store) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let run = try await run(store); let watcher = SessionWatcher(store: store)
        _ = try await watcher.link(runID: run.id, sourcePath: log.path, format: .codex)
        try append(message("- [x] TT-87-01 — ignore user assertion", role: "user"), to: log)
        try append(["timestamp": ISO8601DateFormatter().string(from: .now), "type": "response_item", "payload": ["type": "custom_tool_call_output", "output": "- [x] TT-87-01 — quoted tool output"]], to: log)
        let record = try line(message("TT-87-01: completed — test passed"))
        let file = try FileHandle(forWritingTo: log); try file.seekToEnd(); try file.write(contentsOf: record.dropLast()); try file.close()
        _ = try await watcher.poll()
        let partial = try await store.read()
        XCTAssertEqual(partial.plans[0].todos[0].status, .pending)
        let tail = try FileHandle(forWritingTo: log); try tail.seekToEnd(); try tail.write(contentsOf: Data([10])); try tail.close()
        _ = try await watcher.poll()
        let complete = try await store.read()
        XCTAssertEqual(complete.plans[0].todos[0].status, .completed)
        try line(["type": "session_meta", "payload": ["id": "session-one"]]).write(to: log)
        let reset = try await watcher.poll()
        XCTAssertTrue(reset[0].status.contains("truncated"))
        try append(message("New activity after truncation"), to: log)
        _ = try await watcher.poll()
        let report = try await watcher.reports()
        XCTAssertEqual(report[0].lastSummary, "New activity after truncation")
    }

    func testMissingSourceRecoveryAndInactiveRun() async throws {
        let (directory, log, store) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let run = try await run(store); let watcher = SessionWatcher(store: store)
        _ = try await watcher.link(runID: run.id, sourcePath: log.path, format: .codex)
        let moved = directory.appendingPathComponent("moved.jsonl")
        try FileManager.default.moveItem(at: log, to: moved)
        let missing = try await watcher.poll(); XCTAssertTrue(missing[0].status.hasPrefix("Cannot watch"))
        try FileManager.default.moveItem(at: moved, to: log)
        try append(message("Source recovered"), to: log)
        _ = try await watcher.poll()
        try await store.finishRun(runID: run.id, status: .interrupted)
        try append(message("- [x] TT-87-01 — late message"), to: log)
        let stopped = try await watcher.poll()
        XCTAssertTrue(stopped[0].status.hasPrefix("Stopped"))
        let snapshot = try await store.read()
        XCTAssertEqual(snapshot.plans[0].todos[0].status, .pending)
        XCTAssertEqual(snapshot.runs[0].status, .interrupted)
    }

    func testMarkersAreStrictAndFullIDsArePreserved() {
        let text = """
        I think TT-87-01 is done.
        > - [x] TT-87-01 — quoted
        ```text
        - [x] TT-87-01 — example
        ```
        TT-87-02: completed — real reported evidence
        """
        XCTAssertEqual(SessionObservationParser.completionMarkers(text).map(\.todoID), ["TT-87-02"])
    }

    func testClaudeSessionIsolationAndThinkingExcluded() throws {
        let timestamp = ISO8601DateFormatter().string(from: .now)
        let record: [String: Any] = ["type": "assistant", "sessionId": "claude-one", "timestamp": timestamp, "message": ["role": "assistant", "content": [["type": "text", "text": "- [x] TT-87-02 — tests passed"], ["type": "thinking", "thinking": "private"]]]]
        let data = try line(record)
        let matched = try SessionObservationParser.parse(data, format: .claude, sessionID: "claude-one", eventID: "1")
        XCTAssertEqual(matched?.completions.first?.todoID, "TT-87-02")
        XCTAssertFalse(matched!.message.contains("private"))
        XCTAssertNil(try SessionObservationParser.parse(data, format: .claude, sessionID: "other", eventID: "1"))
    }

    func testSourceTimestampsNoHeartbeatAndNewerExplicitUpdateWins() async throws {
        let (directory, _, store) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let run = try await run(store)
        try await store.update(runID: run.id, todoID: "TT-87-01", status: .blocked, message: "still blocked")
        let baseline = try await store.read()
        let old = SessionObservation(id: "old", occurredAt: .now.addingTimeInterval(-120), message: "older output", completions: [ObservedCompletion(todoID: "TT-87-01", evidence: "old claim")])
        try await store.observe(runID: run.id, observations: [old], source: "test")
        let current = try await store.read()
        XCTAssertEqual(current.runs[0].lastActivityAt, baseline.runs[0].lastActivityAt)
        XCTAssertEqual(current.runs[0].lastTaskUpdateAt, baseline.runs[0].lastTaskUpdateAt)
        XCTAssertEqual(current.plans[0].todos[0].status, .blocked)
        try await store.observe(runID: run.id, observations: [old], source: "test")
        let retried = try await store.read(); XCTAssertEqual(retried, current)
    }
}
