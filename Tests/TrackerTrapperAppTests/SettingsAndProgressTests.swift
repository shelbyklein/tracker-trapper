import AppKit
import XCTest
import TrackerTrapperCore
@testable import TrackerTrapperMenuBar

final class SettingsAndProgressTests: XCTestCase {
    @MainActor func testSetupRejectsInvalidURLs() async throws {
        let plan = try SetupModel.issue(" https://github.com/owner/repo/issues/12?test=1 ")
        XCTAssertEqual(plan.id, "github:owner/repo#12")
        XCTAssertEqual(plan.issueURL, "https://github.com/owner/repo/issues/12")
        for input in ["http://github.com/o/r/issues/1", "https://evil.example/o/r/issues/1", "https://github.com/o/r/pull/1", "https://github.com/o/r/issues/0", "https://user:pass@github.com/o/r/issues/1"] {
            XCTAssertThrowsError(try SetupModel.issue(input))
        }
    }
    @MainActor func testSettingsWindowCanCloseAndReopenWithSameModel() async throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try TrackerStore(url: folder.appendingPathComponent("store.json"))
        let model = MenuModel(store: store, checksGitHub: false, notificationHandler: { _, _, _ in })
        let controller = TrackerSettingsWindow(model: model, notifications: NotificationService(client: FakeNotifications()))
        controller.reveal()
        let window = try XCTUnwrap(controller.window)
        XCTAssertTrue(window.isVisible)
        XCTAssertFalse(window.isReleasedWhenClosed)
        controller.close()
        controller.reveal()
        XCTAssertTrue(controller.window === window)
        XCTAssertTrue(window.isVisible)
        controller.close()
    }
    @MainActor func testBlockedCompletionAndRefreshDoNotRepeat() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try TrackerStore(url: folder.appendingPathComponent("store.json"))
        let plan = Plan(id: "fixture", repository: "org/repo", issueNumber: 1, issueURL: "", title: "Fixture", todos: [Todo(id: "TT-1", description: "Check output")])
        try await store.register(plan)
        let run = try await store.startRun(planID: plan.id, agent: "test", sessionID: "session", repositoryPath: folder.path)
        var notices: [String] = []
        let model = MenuModel(store: store, checksGitHub: false, notificationHandler: { _, subtitle, body in notices.append("\(subtitle): \(body)") })
        try await wait { model.lastRefreshAt != nil }
        XCTAssertTrue(notices.isEmpty)
        try await store.update(runID: run.id, todoID: "TT-1", status: .blocked, message: nil)
        model.refresh()
        try await wait { notices.count == 1 }
        XCTAssertEqual(notices[0], "org/repo #1: Blocked: Check output")
        var time = model.lastRefreshAt; model.refresh()
        try await wait { model.lastRefreshAt != time }
        XCTAssertEqual(notices.count, 1)
        model.dismissAttention(try XCTUnwrap(model.attentionItems.first))
        try await store.update(runID: run.id, todoID: "TT-1", status: .inProgress, message: nil)
        time = model.lastRefreshAt; model.refresh()
        try await wait { model.lastRefreshAt != time }
        try await store.update(runID: run.id, todoID: "TT-1", status: .blocked, message: nil)
        model.refresh(); try await wait { notices.count == 2 }
        try await store.update(runID: run.id, todoID: "TT-1", status: .completed, message: nil, evidence: ["Fixture verified"])
        model.refresh(); try await wait { notices.count == 3 }
        time = model.lastRefreshAt; model.refresh()
        try await wait { model.lastRefreshAt != time }
        XCTAssertEqual(notices.count, 3)
        XCTAssertTrue(notices.last?.contains("Check output") == true)
        let reloaded = MenuModel(store: store, checksGitHub: false, notificationHandler: { _, _, _ in notices.append("unexpected restart") })
        try await wait { reloaded.lastRefreshAt != nil }
        XCTAssertEqual(notices.count, 3)
    }
    @MainActor private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for asynchronous refresh")
    }
}
