import AppKit
import SwiftUI
import XCTest
import TrackerTrapperCore
@testable import TrackerTrapperMenuBar

final class CompletionPopoutTests: XCTestCase {
    @MainActor func testListContextIncludesOnlyAvailableDetails() {
        let local = Plan(localID: "local:test", title: "Finish UI", todos: [], workspacePath: "/work/My Project", creationRequestKey: "test")
        XCTAssertEqual(CompletionPopoutController.context(plan: local, run: nil), CompletionContext(projectTitle: "My Project", details: []))
        let issue = Plan(id: "issue", repository: "owner/repo", issueNumber: 12, issueURL: "", title: "Finish UI", todos: [])
        let run = Run(planID: issue.id, agent: "Codex", sessionID: "session-123", repositoryPath: "/work/repo")
        XCTAssertEqual(CompletionPopoutController.context(plan: issue, run: run), CompletionContext(projectTitle: "repo", details: ["owner/repo · Issue #12", "Codex · Session session-123"]))
    }

    @MainActor func testFinishedListPreviewRendersAndDismisses() async throws {
        _ = NSApplication.shared
        let plan = try XCTUnwrap(CompletionPopoutStyle.testTaskList.taskList)
        XCTAssertEqual(plan.todos.count, 4)
        XCTAssertEqual(plan.todos.filter { $0.parentID != nil }.count, 2)
        var dismissed = false
        let context = CompletionContext(projectTitle: "Tracker Trapper", details: ["shelbyklein/tracker-trapper · Issue #12", "Codex · Example session"])
        let host = NSHostingView(rootView: CompletedTaskList(plan: plan, height: 310, context: context, onDismiss: { dismissed = true }))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 360, height: 310), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertFalse(dismissed)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/tracker-completed-list.png"))
        try await wait { dismissed }
    }

    @MainActor func testTaskRowRendersAndDismissesAfterAnimation() async throws {
        _ = NSApplication.shared
        var dismissed = false
        let host = NSHostingView(rootView: CompletedTaskRow(title: "Review the finished work", onDismiss: { dismissed = true }))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 360, height: 64), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(1100))
        XCTAssertFalse(dismissed)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/tmp/tracker-completed-task-row.png"))
        try await wait { dismissed }
    }

    func testPopoutStylesDescribePlanAndCheckboxState() throws {
        let plan = Plan(id: "plan", repository: "test/repo", issueNumber: 7, issueURL: "", title: "Ship the app", todos: [Todo(id: "TT-1", description: "Verify notifications")])
        var celebrations = CompletionCelebrations()
        celebrations.observe([plan])
        var completed = plan
        completed.todos[0].status = .completed
        celebrations.observe([completed])
        let todo = try XCTUnwrap(celebrations.pendingTodos.first)

        XCTAssertEqual(CompletionPopoutStyle.plan(plan, isClosedIssue: false).systemImage, "party.popper.fill")
        XCTAssertEqual(CompletionPopoutStyle.plan(plan, isClosedIssue: false).accessibilityLabel, "List complete: Ship the app. Dismiss celebration.")
        XCTAssertEqual(CompletionPopoutStyle.plan(plan, isClosedIssue: true).accessibilityLabel, "Issue closed: Ship the app. Dismiss celebration.")
        XCTAssertEqual(CompletionPopoutStyle.todo(todo).systemImage, "checkmark.square.fill")
        XCTAssertEqual(CompletionPopoutStyle.todo(todo).accessibilityLabel, "Checkbox completed: Verify notifications, test/repo #7. Dismiss celebration.")
        XCTAssertEqual(CompletionPopoutStyle.testCheckbox.accessibilityLabel, "Test checkbox completed popup. Dismiss celebration.")
        XCTAssertEqual(CompletionPopoutStyle.testTaskList.systemImage, "party.popper.fill")
        XCTAssertEqual(CompletionPopoutStyle.testTaskList.accessibilityLabel, "Test finished task list popup. Dismiss celebration.")
    }

    @MainActor func testPopoutRequiresAWindowAnchor() {
        let controller = CompletionPopoutController()
        let detached = NSView(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        let plan = Plan(id: "plan", repository: "test/repo", issueNumber: 1, issueURL: "", title: "Done", todos: [])

        XCTAssertFalse(controller.show(plan: plan, isClosedIssue: false, anchoredTo: detached, onDismiss: {}))
        XCTAssertNil(controller.panel)
    }

    @MainActor func testLastCheckboxPopupHandsOffToPlanPopup() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try TrackerStore(url: folder.appendingPathComponent("store.json"))
        let plan = try await store.registerLocal(title: "One task", todos: [Todo(id: "T", description: "Only checkbox")], workspacePath: nil, creationRequestKey: UUID().uuidString)
        let run = try await store.startRun(planID: plan.id, agent: "test", sessionID: "test", repositoryPath: folder.path)
        let model = MenuModel(store: store, checksGitHub: false, notificationHandler: { _, _, _ in }, celebrationsEnabled: { true })
        var order: [String] = []
        model.todoCelebrationPresenter = { order.append("todo:\($0.todoID)"); return true }
        model.celebrationPresenter = { order.append("plan:\($0.id)"); return true }
        try await wait { model.lastRefreshAt != nil }

        try await store.update(runID: run.id, todoID: "T", status: .completed, message: nil, evidence: ["Verified"])
        model.refresh()
        try await wait { model.celebratingTodoID != nil }
        XCTAssertEqual(order, ["todo:T"])
        XCTAssertNil(model.celebratingID)

        model.dismissCelebration()
        try await wait { model.celebratingID == plan.id }
        XCTAssertEqual(order, ["todo:T", "plan:\(plan.id)"])
        XCTAssertNil(model.celebratingTodoID)

        model.dismissCelebration()
        XCTAssertTrue(model.celebrations.pending.isEmpty)
        XCTAssertTrue(model.celebrations.pendingTodos.isEmpty)
    }

    @MainActor func testIndividualCheckboxShowsCheckboxPopoutWithoutCompletingPlan() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try TrackerStore(url: folder.appendingPathComponent("store.json"))
        let plan = try await store.registerLocal(
            title: "Two tasks",
            todos: [Todo(id: "A", description: "First checkbox"), Todo(id: "B", description: "Second checkbox")],
            workspacePath: nil,
            creationRequestKey: UUID().uuidString
        )
        let run = try await store.startRun(planID: plan.id, agent: "test", sessionID: "test", repositoryPath: folder.path)
        let model = MenuModel(store: store, checksGitHub: false, notificationHandler: { _, _, _ in }, celebrationsEnabled: { true })
        var todoPopouts: [TodoCompletionCelebration] = []
        var planPopouts = 0
        model.todoCelebrationPresenter = { todoPopouts.append($0); return true }
        model.celebrationPresenter = { _ in planPopouts += 1; return true }
        try await wait { model.lastRefreshAt != nil }

        try await store.update(runID: run.id, todoID: "A", status: .completed, message: nil, evidence: ["Checked"])
        model.refresh()
        try await wait { model.celebratingTodoID != nil }
        XCTAssertEqual(todoPopouts.map(\.todoDescription), ["First checkbox"])
        XCTAssertEqual(CompletionPopoutStyle.todo(todoPopouts[0]).systemImage, "checkmark.square.fill")
        XCTAssertEqual(planPopouts, 0)
        XCTAssertTrue(model.celebrations.pending.isEmpty)
        XCTAssertEqual(model.snapshot.plans.first?.todos.filter { $0.status == .completed }.count, 1)

        model.dismissCelebration()
        XCTAssertNil(model.celebratingTodoID)
        XCTAssertTrue(model.celebrations.pendingTodos.isEmpty)
        let before = model.lastRefreshAt
        model.refresh()
        try await wait { model.lastRefreshAt != before }
        XCTAssertEqual(todoPopouts.count, 1)
        XCTAssertEqual(planPopouts, 0)
    }

    @MainActor func testLocalCompletionPresentsWithoutOpeningMenuAndAutoDismisses() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try TrackerStore(url: folder.appendingPathComponent("store.json"))
        let plan = try await store.registerLocal(title: "Finished list", todos: [Todo(id: "T", description: "Task")], workspacePath: nil, creationRequestKey: UUID().uuidString)
        let run = try await store.startRun(planID: plan.id, agent: "test", sessionID: "test", repositoryPath: folder.path)
        let model = MenuModel(store: store, checksGitHub: false, notificationHandler: { _, _, _ in }, celebrationsEnabled: { true })
        var shown: [String] = []
        var hides = 0
        model.celebrationPresenter = { shown.append($0.id); return true }
        model.celebrationDismissal = { hides += 1 }
        try await wait { model.lastRefreshAt != nil }
        try await store.update(runID: run.id, todoID: "T", status: .completed, message: nil, evidence: ["Verified"])
        model.refresh()
        try await wait { model.celebratingID == plan.id }
        XCTAssertEqual(shown, [plan.id])
        let start = Date()
        try await wait { model.celebrations.dismissedPlanIDs.contains(plan.id) }
        XCTAssertGreaterThan(Date().timeIntervalSince(start), 5)
        XCTAssertLessThan(Date().timeIntervalSince(start), 7)
        XCTAssertNil(model.celebratingID)
        XCTAssertEqual(hides, 1)
        model.refresh()
        try await wait { model.snapshot.plans.isEmpty }
        let reloaded = MenuModel(store: store, checksGitHub: false, notificationHandler: { _, _, _ in }, celebrationsEnabled: { true })
        reloaded.celebrationPresenter = { shown.append($0.id); return true }
        try await wait { reloaded.lastRefreshAt != nil }
        XCTAssertEqual(shown, [plan.id])
        XCTAssertTrue(reloaded.celebrations.pending.isEmpty)
    }

    @MainActor func testGitHubClosurePresentsEvenThoughIssueLeavesMainPanel() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try TrackerStore(url: folder.appendingPathComponent("store.json"))
        let plan = Plan(id: UUID().uuidString, repository: "test/repo", issueNumber: 1, issueURL: "", title: "Closed issue", todos: [Todo(id: "T", description: "Unfinished")])
        try await store.register(plan)
        var closed = false
        var checks = 0
        var shown: [String] = []
        let model = MenuModel(store: store, notificationHandler: { _, _, _ in }, githubStatusCheck: { _ in checks += 1; return closed }, celebrationsEnabled: { true })
        model.celebrationPresenter = { shown.append($0.id); return true }
        try await wait { model.lastRefreshAt != nil && checks == 1 }
        XCTAssertTrue(shown.isEmpty)
        closed = true
        model.refreshManually()
        try await wait { !model.isManualRefreshing && model.celebratingID == plan.id }
        XCTAssertEqual(shown, [plan.id])
        XCTAssertTrue(model.snapshot.plans.isEmpty)
        let current = try await store.read()
        XCTAssertEqual(current.plans.first?.todos.first?.status, .pending)
        model.dismissCelebration()
        model.refreshManually()
        try await wait { !model.isManualRefreshing }
        XCTAssertEqual(shown, [plan.id])
    }

    @MainActor func testUnavailablePresenterRetriesAndDisabledSettingConsumesWithoutReplay() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try TrackerStore(url: folder.appendingPathComponent("store.json"))
        let plan = try await store.registerLocal(title: "Local", todos: [Todo(id: "T", description: "Task")], workspacePath: nil, creationRequestKey: UUID().uuidString)
        let run = try await store.startRun(planID: plan.id, agent: "test", sessionID: "test", repositoryPath: folder.path)
        var enabled = true
        var available = false
        var presentations = 0
        let model = MenuModel(store: store, checksGitHub: false, notificationHandler: { _, _, _ in }, celebrationsEnabled: { enabled })
        model.celebrationPresenter = { _ in if available { presentations += 1 }; return available }
        try await wait { model.lastRefreshAt != nil }
        try await store.update(runID: run.id, todoID: "T", status: .completed, message: nil, evidence: ["Verified"])
        model.refresh()
        try await wait { model.celebrations.pending.count == 1 }
        XCTAssertNil(model.celebratingID)
        available = true
        model.refresh()
        try await wait { model.celebratingID == plan.id }
        enabled = false
        model.refresh()
        try await wait { model.celebrations.pending.isEmpty }
        XCTAssertNil(model.celebratingID)
        enabled = true
        let before = model.lastRefreshAt
        model.refresh()
        try await wait { model.lastRefreshAt != before }
        XCTAssertEqual(presentations, 1)
    }

    @MainActor func testOpenMenuUsesInlineCelebrationAndQueuesSimultaneousLists() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try TrackerStore(url: folder.appendingPathComponent("store.json"))
        var runs: [Run] = []
        for title in ["First", "Second"] {
            let plan = try await store.registerLocal(title: title, todos: [Todo(id: "T", description: "Task")], workspacePath: nil, creationRequestKey: title)
            runs.append(try await store.startRun(planID: plan.id, agent: "test", sessionID: title, repositoryPath: folder.path))
        }
        let model = MenuModel(store: store, checksGitHub: false, notificationHandler: { _, _, _ in }, celebrationsEnabled: { true })
        var shown: [String] = []
        model.celebrationPresenter = { shown.append($0.id); return true }
        try await wait { model.lastRefreshAt != nil }
        model.panelDidOpen()
        for run in runs {
            try await store.update(runID: run.id, todoID: "T", status: .completed, message: nil, evidence: ["Verified"])
        }
        model.refresh()
        try await wait { model.celebrations.pending.count == 2 }
        XCTAssertNotNil(model.celebratingID)
        XCTAssertTrue(shown.isEmpty)
        let firstID = try XCTUnwrap(model.celebratingID)
        model.panelDidClose()
        XCTAssertEqual(shown, [firstID])
        model.dismissCelebration()
        XCTAssertEqual(shown.count, 2)
        XCTAssertNotEqual(shown[0], shown[1])
        model.dismissCelebration()
        XCTAssertTrue(model.celebrations.pending.isEmpty)
        XCTAssertNil(model.celebratingID)
    }

    @MainActor func testPopoutIsNonactivatingAndClampedToMenuBarScreen() throws {
        _ = NSApplication.shared
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        let button = try XCTUnwrap(item.button)
        button.title = "✓"
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let controller = CompletionPopoutController()
        defer { controller.hide() }
        let plan = Plan(id: "preview", repository: "test/repo", issueNumber: 1, issueURL: "", title: "A completed issue", todos: [])
        XCTAssertTrue(controller.show(plan: plan, isClosedIssue: true, anchoredTo: button, onDismiss: {}))
        let panel = try XCTUnwrap(controller.panel)
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertFalse(panel.isKeyWindow)
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, frontmost)
        controller.hide()
        XCTAssertFalse(panel.isVisible)
        // A full/hidden menu bar can put the status item offscreen. Fall back to
        // the top-right of the active display instead of losing the celebration.
        let hiddenAnchor = NSWindow(contentRect: NSRect(x: -100000, y: -100000, width: 24, height: 24), styleMask: .borderless, backing: .buffered, defer: false)
        hiddenAnchor.isReleasedWhenClosed = false
        XCTAssertNil(hiddenAnchor.screen)
        XCTAssertTrue(controller.show(plan: plan, isClosedIssue: true, anchoredTo: try XCTUnwrap(hiddenAnchor.contentView), onDismiss: {}))
        XCTAssertTrue(try XCTUnwrap(NSScreen.main).visibleFrame.contains(panel.frame))
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, frontmost)
        controller.hide()
        let screen = NSRect(x: -1440, y: 0, width: 1440, height: 875)
        for x in [-1440.0, -20.0] {
            let frame = CompletionPopoutController.frame(anchor: NSRect(x: x, y: 875, width: 22, height: 25), screen: screen)
            XCTAssertTrue(screen.contains(frame))
            XCTAssertEqual(frame.size, NSSize(width: 72, height: 64))
            XCTAssertEqual(frame.maxY, screen.maxY - 4)
        }
    }

    @MainActor private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<1200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for celebration lifecycle")
    }
}
