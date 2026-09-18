import XCTest
@testable import TrackerTrapperCore

final class GitHubChecklistTests: XCTestCase {
    func testBothChecklistFormatsIgnoreExamplesAndGeneratedProgress() {
        let todos = GitHubChecklist.parse("""
        - [ ] **TT-01 — First task.** Check: passes.
        - [x] **TT-02** — Second task.
        ```markdown
        - [x] **TT-EXAMPLE** — Example only.
        ```
        <!-- tracker-trapper:progress:start -->
        - [x] **TT-01** — Mirrored state.
        <!-- tracker-trapper:progress:end -->
        """)
        XCTAssertEqual(todos.map(\.id), ["TT-01", "TT-02"])
        XCTAssertEqual(todos[0].acceptance, "passes.")
        XCTAssertEqual(todos[1].status, .completed)
    }

    func testStageHeadingsScopeChildrenAndIgnoreExamples() throws {
        let todos = GitHubChecklist.parse("""
        ## Stage A — Design
        - [x] **TT-A-1** — First
        ### Acceptance checks
        - [ ] **TT-A-2** — Second
        ```markdown
        ## Stage Z — Example
        ```
        - [ ] **TT-A-3** — Third
        ## B: Build
        - [ ] **TT-B-1** — Fourth
        ## Notes
        - [ ] **TT-OTHER** — Ungrouped
        ## Phase C — Ship
        - [ ] **TT-C-1** — Fifth
        """)
        XCTAssertEqual(todos.map(\.stage), ["Stage A — Design", "Stage A — Design", "Stage A — Design", "B: Build", nil, "Phase C — Ship"])
        let data = try JSONEncoder().encode(todos)
        XCTAssertEqual(try JSONDecoder().decode([Todo].self, from: data), todos)
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(todos[0])) as! [String: Any]
        old.removeValue(forKey: "stage")
        XCTAssertNil(try JSONDecoder().decode(Todo.self, from: JSONSerialization.data(withJSONObject: old)).stage)
    }

    func testRefreshAddsNewScopeAndPreservesLocalEvidence() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try TrackerStore(url: dir.appendingPathComponent("store.json"))
        let plan = try await store.register(Plan(repository: "org/repo", issueNumber: 86, issueURL: "https://github.com/org/repo/issues/86", title: "Old", todos: [Todo(id: "OLD", description: "Investigation", status: .completed, evidence: ["saved"]), Todo(id: "TT-01", description: "Old description", status: .completed, evidence: ["local passing tests"])]))
        let incoming = GitHubChecklist.parse("## Stage A — Implementation\n- [ ] **TT-01** — New description\n- [ ] **TT-02** — New implementation work")
        try await store.reconcileGitHubChecklist(planID: plan.id, title: "Current", todos: incoming)
        var saved = try await store.read()
        XCTAssertEqual(saved.plans[0].todos.count, 3)
        XCTAssertEqual(saved.plans[0].todos[0].evidence, ["saved"])
        XCTAssertEqual(saved.plans[0].todos[1].description, "New description")
        XCTAssertEqual(saved.plans[0].todos[1].stage, "Stage A — Implementation")
        XCTAssertEqual(saved.plans[0].todos[1].status, .completed)
        XCTAssertEqual(saved.plans[0].todos[1].evidence, ["local passing tests"])
        XCTAssertEqual(saved.plans[0].todos[2].status, .pending)
        let unchanged = saved
        try await store.reconcileGitHubChecklist(planID: plan.id, title: "Current", todos: incoming)
        saved = try await store.read()
        XCTAssertEqual(saved, unchanged)
        XCTAssertTrue(saved.outbox.isEmpty)
    }
}
