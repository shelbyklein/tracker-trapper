import AppKit
import SwiftUI
import XCTest
import TrackerTrapperCore
@testable import TrackerTrapperMenuBar

final class GlassLayoutTests: XCTestCase {
    @MainActor func testPopulatedCardsFitPopoverInBothAppearances() async throws {
        var plan = Plan(repository: "studio/side-project", issueNumber: 24,
                        issueURL: "https://github.com/studio/side-project/issues/24", title: "Build the landing page",
                        todos: [Todo(id: "A", description: "Create the first draft"),
                                Todo(id: "B", description: "Connect the page"),
                                Todo(id: "C", description: "Add the contact form"),
                                Todo(id: "D", description: "Check mobile layout"),
                                Todo(id: "E", description: "Review the finished page")])
        plan.todos[0].status = .completed; plan.todos[1].status = .completed
        plan.todos[2].status = .inProgress; plan.nextTodoID = "D"
        let run = Run(planID: plan.id, agent: "Codex", sessionID: "visual-review", repositoryPath: "")
        for (name, scheme, opaque) in [("light", ColorScheme.light, false), ("dark", .dark, false), ("opaque", .light, true)] {
            let content = VStack(alignment: .leading, spacing: 14) {
                HStack { Text("Tracker Trapper").font(.system(size: 17, weight: .bold)); Spacer(); Image(systemName: "gearshape"); Image(systemName: "bell"); Text("Refresh").font(.caption) }
                PlanCard(plan: plan, runs: [run], watches: [], onLink: { _ in }, onUnlink: { _ in })
                Text("No GitHub updates pending.").font(.caption).foregroundStyle(.secondary)
            }.padding(18).frame(width: 420).trackerGlass(radius: 26, shell: true)
                .environment(\.colorScheme, scheme).environment(\.trackerOpaqueSurfaces, opaque)
            let host = NSHostingView(rootView: content)
            let size = host.fittingSize
            XCTAssertEqual(size.width, 420, accuracy: 1)
            XCTAssertGreaterThan(size.height, 300)
            XCTAssertLessThan(size.height, 650, "A normal five-task card must fit comfortably in the panel")
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            window.contentView = host
            window.orderFrontRegardless()
            try await Task.sleep(for: .milliseconds(200))
            host.layoutSubtreeIfNeeded()
            if let directory = ProcessInfo.processInfo.environment["TT_GLASS_REVIEW_DIR"] {
                let capture = Process()
                capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                capture.arguments = ["-x", "-l", String(window.windowNumber), URL(fileURLWithPath: directory).appendingPathComponent("card-\(name).png").path]
                try capture.run(); capture.waitUntilExit()
                XCTAssertEqual(capture.terminationStatus, 0)
            }
            window.orderOut(nil)
        }
    }
}
