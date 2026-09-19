import AppKit
import SwiftUI
import TrackerTrapperCore

struct CompletionContext: Equatable, Sendable {
    var projectTitle: String?
    var details: [String]

    static let empty = CompletionContext(projectTitle: nil, details: [])
}

/// A tiny celebration that never activates the app or takes typing focus.
@MainActor final class CompletionPopoutController {
    private(set) var panel: NSPanel?

    @discardableResult
    func show(plan: Plan, isClosedIssue: Bool, run: Run? = nil, anchoredTo button: NSView, onDismiss: @escaping () -> Void) -> Bool {
        show(style: .plan(plan, isClosedIssue: isClosedIssue), context: Self.context(plan: plan, run: run), anchoredTo: button, onDismiss: onDismiss)
    }

    static func context(plan: Plan, run: Run?) -> CompletionContext {
        var projectTitle: String?
        var details: [String] = []
        if let path = plan.workspacePath ?? run?.repositoryPath, !path.isEmpty {
            projectTitle = URL(fileURLWithPath: path).lastPathComponent
        }
        if plan.isGitHub && !plan.repository.isEmpty {
            details.append(plan.repository + (plan.issueNumber > 0 ? " · Issue #\(plan.issueNumber)" : ""))
        }
        if let run, !run.sessionID.isEmpty {
            details.append("\(run.agent) · Session \(run.sessionID)")
        }
        return CompletionContext(projectTitle: projectTitle, details: details)
    }

    @discardableResult
    func show(todo: TodoCompletionCelebration, anchoredTo button: NSView, onDismiss: @escaping () -> Void) -> Bool {
        show(style: .todo(todo), anchoredTo: button, onDismiss: onDismiss)
    }

    @discardableResult
    func showTestCheckbox(anchoredTo button: NSView, onDismiss: @escaping () -> Void) -> Bool {
        show(style: .testCheckbox, anchoredTo: button, onDismiss: onDismiss)
    }

    @discardableResult
    func showTestTaskList(anchoredTo button: NSView, onDismiss: @escaping () -> Void) -> Bool {
        show(style: .testTaskList, context: CompletionContext(projectTitle: "Tracker Trapper", details: ["shelbyklein/tracker-trapper · Issue #12", "Codex · Example session"]), anchoredTo: button, onDismiss: onDismiss)
    }

    @discardableResult
    private func show(style: CompletionPopoutStyle, context: CompletionContext = .empty, anchoredTo button: NSView, onDismiss: @escaping () -> Void) -> Bool {
        guard let window = button.window, let screen = window.screen ?? NSScreen.main else { return false }
        // macOS can leave a hidden/overflowed status item without a screen. Keep
        // the celebration visible at the top-right until its icon is available.
        let anchor = window.screen != nil
            ? window.convertToScreen(button.convert(button.bounds, to: nil))
            : NSRect(x: screen.visibleFrame.maxX - 36, y: screen.visibleFrame.maxY + 4, width: 24, height: 24)
        let list = style.taskList
        let contextCount = min(context.details.count, 3)
        let contextHeight = contextCount == 0 ? 0 : contextCount * 26 + max(contextCount - 1, 0) * 6 + 12
        let projectHeight = context.projectTitle == nil ? 0 : 15
        let requestedHeight = 76 + projectHeight + (list?.todos.count ?? 0) * 34 + contextHeight
        let height: CGFloat = list == nil ? 64 : min(CGFloat(requestedHeight), screen.visibleFrame.height - 24)
        let frame = Self.frame(anchor: anchor, screen: screen.visibleFrame, width: 360, height: height)
        let panel = self.panel ?? CelebrationPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Tracker Trapper celebration"
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.animationBehavior = .none
        if let title = style.taskTitle {
            panel.contentView = NSHostingView(rootView: CompletedTaskRow(title: title, onDismiss: onDismiss))
        } else if let list {
            panel.contentView = NSHostingView(rootView: CompletedTaskList(plan: list, height: height, context: context, onDismiss: onDismiss))
        }
        panel.setFrame(frame, display: false)
        self.panel = panel
        panel.orderFrontRegardless()
        return panel.isVisible
    }

    func hide() { panel?.orderOut(nil) }

    static func frame(anchor: NSRect, screen: NSRect, width: CGFloat = 72, height: CGFloat = 64) -> NSRect {
        let x = min(max(anchor.midX - width / 2, screen.minX + 8), screen.maxX - width - 8)
        let y = max(screen.minY + 8, min(anchor.minY - 4, screen.maxY) - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

enum CompletionPopoutStyle {
    case plan(Plan, isClosedIssue: Bool)
    case todo(TodoCompletionCelebration)
    case testCheckbox
    case testTaskList

    var taskList: Plan? {
        switch self {
        case .plan(let plan, _): return plan
        case .testTaskList:
            return Plan(id: "preview", repository: "", issueNumber: 0, issueURL: "", title: "Task list complete", todos: [
                Todo(id: "1", description: "Review the design", status: .completed),
                Todo(id: "2", description: "Build the changes", status: .completed, parentID: "1"),
                Todo(id: "3", description: "Check the result", status: .completed, parentID: "1"),
                Todo(id: "4", description: "Finish the task list", status: .completed)
            ])
        default: return nil
        }
    }

    var taskTitle: String? {
        switch self {
        case .todo(let todo): todo.todoDescription
        case .testCheckbox: "Review the finished work"
        case .plan, .testTaskList: nil
        }
    }

    var systemImage: String {
        switch self {
        case .plan, .testTaskList: "party.popper.fill"
        case .todo, .testCheckbox: "checkmark.square.fill"
        }
    }

    var color: Color {
        switch self {
        case .plan, .testTaskList: .yellow
        case .todo, .testCheckbox: .green
        }
    }

    var accessibilityLabel: String {
        switch self {
        case let .plan(plan, isClosedIssue):
            "\(isClosedIssue ? "Issue closed" : "List complete"): \(plan.title). Dismiss celebration."
        case let .todo(todo):
            "Checkbox completed: \(todo.todoDescription), \(todo.planSubtitle). Dismiss celebration."
        case .testCheckbox:
            "Test checkbox completed popup. Dismiss celebration."
        case .testTaskList:
            "Test finished task list popup. Dismiss celebration."
        }
    }
}

private final class CelebrationPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct CompletedTaskList: View {
    let plan: Plan
    let height: CGFloat
    var context: CompletionContext = .empty
    let onDismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var completed = Set<String>()
    @State private var leaving = false
    @State private var titleComplete = false
    @State private var confetti = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(.secondary, lineWidth: 1.5)
                    Image(systemName: "party.popper.fill")
                        .font(.system(size: 17)).foregroundStyle(.yellow)
                        .scaleEffect(titleComplete ? 1.45 : 0.35)
                        .opacity(titleComplete ? 1 : 0)
                        .zIndex(1)
                    if titleComplete && !reduceMotion {
                        ForEach(0..<10, id: \.self) { index in
                            let angle = Double(index) * 2.39996
                            Capsule().fill([Color.yellow, .pink, .cyan, .mint][index % 4])
                                .frame(width: 2, height: 4)
                                .rotationEffect(.degrees(Double(index * 47)))
                                .offset(x: cos(angle) * (confetti ? 22 : 3),
                                        y: sin(angle) * (confetti ? 22 : 3))
                                .opacity(confetti ? 0 : 1)
                        }
                    }
                }.frame(width: 19, height: 19).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    if let projectTitle = context.projectTitle {
                        Text(projectTitle)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(projectTitle)
                    }
                    Text(plan.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                }
                Spacer()
                Button(action: onDismiss) { Image(systemName: "xmark").font(.caption) }
                    .buttonStyle(.plain).accessibilityLabel("Dismiss task list")
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(plan.todos) { todo in
                            let done = completed.contains(todo.id)
                            HStack(spacing: 10) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 4).strokeBorder(.secondary, lineWidth: 1.5)
                                    RoundedRectangle(cornerRadius: 4).fill(Color.green).opacity(done ? 1 : 0)
                                    Image(systemName: todo.status == .skipped ? "minus" : "checkmark")
                                        .font(.system(size: 11, weight: .bold)).foregroundStyle(.black)
                                        .opacity(done || todo.status == .skipped ? 1 : 0)
                                }.frame(width: 19, height: 19)
                                Text(todo.description).font(.system(size: 12)).lineLimit(1)
                                    .foregroundStyle(done ? .secondary : .primary)
                                    .overlay {
                                        GeometryReader { geometry in
                                            Rectangle().fill(Color.primary.opacity(0.6))
                                                .frame(width: done ? geometry.size.width : 0, height: 1)
                                                .position(x: (done ? geometry.size.width : 0) / 2, y: geometry.size.height / 2)
                                        }
                                    }
                                Spacer(minLength: 0)
                            }
                            .padding(.leading, todo.parentID == nil ? 0 : 22)
                            .frame(height: 34)
                            .id(todo.id)
                        }
                    }
                }
                .task {
                    do {
                        if let last = plan.todos.last { proxy.scrollTo(last.id, anchor: .bottom) }
                        try await Task.sleep(for: .milliseconds(900))
                        for todo in plan.todos.reversed() {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) {
                                proxy.scrollTo(todo.id, anchor: .center)
                                if todo.status == .completed { completed.insert(todo.id) }
                            }
                            if !reduceMotion { try await Task.sleep(for: .milliseconds(550)) }
                        }
                        // Let the top task finish crossing out before celebrating the title.
                        try await Task.sleep(for: .milliseconds(180))
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.65)) {
                            titleComplete = true
                        }
                        try await Task.sleep(for: .milliseconds(50))
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5)) { confetti = true }
                        try await Task.sleep(for: .milliseconds(3000))
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4)) { leaving = true }
                        try await Task.sleep(for: .milliseconds(400))
                        onDismiss()
                    } catch { }
                }
            }
            if !context.details.isEmpty {
                VStack(spacing: 6) {
                    ForEach(Array(context.details.prefix(3).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(line)
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                            .background(.white.opacity(0.07), in: Capsule())
                            .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
                    }
                }
            }
        }
        .padding(18).frame(width: 352, height: height - 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.2)))
        .opacity(leaving ? 0 : 1).offset(y: leaving && !reduceMotion ? -6 : 0)
        .frame(width: 360, height: height)
    }
}

struct CompletedTaskRow: View {
    let title: String
    let onDismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var checked = false
    @State private var crossed = false
    @State private var leaving = false

    var body: some View {
        Button(action: onDismiss) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(checked ? Color.green : Color.clear)
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(checked ? Color.green : Color.white.opacity(0.65), lineWidth: 1.5)
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(.black)
                        .opacity(checked ? 1 : 0)
                }.frame(width: 22, height: 22)
                Text(title).font(.system(size: 13, weight: .medium))
                    .lineLimit(1).truncationMode(.tail)
                    .foregroundStyle(.white.opacity(crossed ? 0.65 : 1))
                    .overlay(alignment: .leading) {
                        GeometryReader { geometry in
                            Rectangle().fill(.white.opacity(0.8))
                                .frame(width: crossed ? geometry.size.width : 0, height: 1.5)
                                .position(x: (crossed ? geometry.size.width : 0) / 2, y: geometry.size.height / 2)
                        }.allowsHitTesting(false)
                    }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18).frame(width: 352, height: 52)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.2)))
            .opacity(leaving ? 0 : 1)
            .offset(y: leaving && !reduceMotion ? -6 : 0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Completed: \(title). Dismiss completion.")
        .frame(width: 360, height: 64)
        .task {
            do {
                if reduceMotion { checked = true; crossed = true }
                else {
                    try await Task.sleep(for: .milliseconds(300))
                    withAnimation(.easeOut(duration: 0.25)) { checked = true }
                    try await Task.sleep(for: .milliseconds(200))
                    withAnimation(.easeInOut(duration: 0.45)) { crossed = true }
                }
                try await Task.sleep(for: .milliseconds(1200))
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4)) { leaving = true }
                try await Task.sleep(for: .milliseconds(400))
                onDismiss()
            } catch { /* Replaced or dismissed while animating. */ }
        }
    }
}

private struct PopupBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let body = CGRect(x: 4, y: 8, width: rect.width - 8, height: rect.height - 12)
        path.addRoundedRect(in: body, cornerSize: CGSize(width: 16, height: 16))
        path.move(to: CGPoint(x: rect.midX - 8, y: body.minY + 1))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + 8, y: body.minY + 1))
        path.closeSubpath()
        return path
    }
}

private struct CompletionPopout: View {
    let style: CompletionPopoutStyle
    let onDismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burst = false

    var body: some View {
        Button(action: onDismiss) {
            ZStack {
                PopupBubbleShape()
                    .fill(.regularMaterial)
                    .overlay(PopupBubbleShape().stroke(.white.opacity(0.22), lineWidth: 1))
                Image(systemName: style.systemImage)
                    .font(.system(size: 24, weight: .semibold)).foregroundStyle(style.color)
                    .offset(y: 4)
                    .rotationEffect(.degrees(!reduceMotion && !burst ? -12 : 0))
                if !reduceMotion {
                    ForEach(0..<10, id: \.self) { index in
                        let angle = Double(index) * 2.39996
                        Capsule()
                            .fill([Color.yellow, .pink, .cyan, .mint][index % 4])
                            .frame(width: 2, height: 4)
                            .rotationEffect(.degrees(Double(index * 47)))
                            .offset(x: cos(angle) * (burst ? 19 : 4),
                                    y: sin(angle) * (burst ? 19 : 4) + 4)
                            .opacity(burst ? 0 : 1)
                    }
                }
            }
            .frame(width: 72, height: 64)
            .contentShape(PopupBubbleShape())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.accessibilityLabel)
        .task {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1)) { burst = true }
        }
    }
}
