import Foundation

public struct TodoCompletionCelebration: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let planID: String
    public let planTitle: String
    public let planSubtitle: String
    public let todoID: String
    public let todoDescription: String

    init(plan: Plan, todo: Todo) {
        id = "\(plan.id):\(todo.id):\(todo.revision)"
        planID = plan.id
        planTitle = plan.title
        planSubtitle = plan.displaySubtitle
        todoID = todo.id
        todoDescription = todo.description
    }
}

/// A completion is celebrated once after an observed transition, not on import.
/// Pending celebrations survive closing/restarting the menu-bar app.
public struct CompletionCelebrations: Codable, Equatable, Sendable {
    public private(set) var pending: [Plan] = []
    public private(set) var dismissedPlanIDs: Set<String> = []
    private var observedCompletion: [String: Bool] = [:]
    // Optional so celebration state written by older app versions still decodes.
    private var observedIssueClosure: [String: Bool]?
    private var pendingTodoStorage: [TodoCompletionCelebration]?
    private var observedTodoStatuses: [String: [String: TodoStatus]]?

    public var pendingTodos: [TodoCompletionCelebration] { pendingTodoStorage ?? [] }

    public init() {}

    public static func isComplete(_ plan: Plan) -> Bool {
        !plan.todos.isEmpty && plan.todos.contains { $0.status == .completed }
            && plan.todos.allSatisfy { $0.status == .completed || $0.status == .skipped }
    }

    public mutating func observe(_ plans: [Plan]) {
        let currentIDs = Set(plans.map(\.id))
        pending.removeAll { !currentIDs.contains($0.id) }
        pendingTodoStorage?.removeAll { !currentIDs.contains($0.planID) }
        observedTodoStatuses = observedTodoStatuses?.filter { currentIDs.contains($0.key) }
        for plan in plans {
            let statuses = Dictionary(uniqueKeysWithValues: plan.todos.map { ($0.id, $0.status) })
            if let previous = observedTodoStatuses?[plan.id] {
                for todo in plan.todos where todo.status == .completed && previous[todo.id] != .completed {
                    let celebration = TodoCompletionCelebration(plan: plan, todo: todo)
                    if !(pendingTodoStorage ?? []).contains(where: { $0.id == celebration.id }) {
                        if pendingTodoStorage == nil { pendingTodoStorage = [] }
                        pendingTodoStorage?.append(celebration)
                    }
                }
                pendingTodoStorage?.removeAll { celebration in
                    celebration.planID == plan.id && statuses[celebration.todoID] != .completed
                }
            }
            if observedTodoStatuses == nil { observedTodoStatuses = [:] }
            observedTodoStatuses?[plan.id] = statuses

            let complete = Self.isComplete(plan) || observedIssueClosure?[plan.id] == true
            if !complete {
                pending.removeAll { $0.id == plan.id }
                dismissedPlanIDs.remove(plan.id)
            } else if observedCompletion[plan.id] == false {
                pending.removeAll { $0.id == plan.id }
                pending.append(plan)
                dismissedPlanIDs.remove(plan.id)
            } else if let index = pending.firstIndex(where: { $0.id == plan.id }) {
                pending[index] = plan
            }
            observedCompletion[plan.id] = complete
        }
    }

    /// A first status fetch establishes a baseline. Only an observed open -> closed
    /// transition celebrates; closing an issue never completes its unfinished todos.
    public mutating func observeGitHubIssue(_ plan: Plan, isClosed: Bool) {
        guard plan.isGitHub else { return }
        let wasClosed = observedIssueClosure?[plan.id]
        if observedIssueClosure == nil { observedIssueClosure = [:] }
        observedIssueClosure?[plan.id] = isClosed
        if isClosed {
            if wasClosed == false, !dismissedPlanIDs.contains(plan.id),
               !pending.contains(where: { $0.id == plan.id }) {
                pending.append(plan)
            }
            observedCompletion[plan.id] = true
        } else if wasClosed == true {
            pending.removeAll { $0.id == plan.id }
            dismissedPlanIDs.remove(plan.id)
            observedCompletion[plan.id] = Self.isComplete(plan)
        }
    }

    public func isClosedIssue(_ planID: String) -> Bool {
        observedIssueClosure?[planID] == true
    }

    public mutating func acknowledge(_ planID: String) {
        guard pending.contains(where: { $0.id == planID }) else { return }
        pending.removeAll { $0.id == planID }
        dismissedPlanIDs.insert(planID)
    }

    public mutating func acknowledgeTodo(_ celebrationID: String) {
        pendingTodoStorage?.removeAll { $0.id == celebrationID }
    }

    public func hasPendingTodo(for planID: String) -> Bool {
        pendingTodos.contains { $0.planID == planID }
    }

    /// Turning animation off still acknowledges completed cards when the panel opens.
    @discardableResult public mutating func acknowledgeWithoutAnimation() -> Bool {
        let ids = pending.map(\.id)
        for id in ids { acknowledge(id) }
        let hadTodos = !(pendingTodoStorage ?? []).isEmpty
        pendingTodoStorage?.removeAll()
        return !ids.isEmpty || hadTodos
    }
}
