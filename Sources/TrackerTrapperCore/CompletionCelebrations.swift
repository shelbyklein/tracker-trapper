import Foundation

/// A completion is celebrated once after an observed transition, not on import.
/// Pending celebrations survive closing/restarting the menu-bar app.
public struct CompletionCelebrations: Codable, Equatable, Sendable {
    public private(set) var pending: [Plan] = []
    public private(set) var dismissedPlanIDs: Set<String> = []
    private var observedCompletion: [String: Bool] = [:]

    public init() {}

    public static func isComplete(_ plan: Plan) -> Bool {
        !plan.todos.isEmpty && plan.todos.contains { $0.status == .completed }
            && plan.todos.allSatisfy { $0.status == .completed || $0.status == .skipped }
    }

    public mutating func observe(_ plans: [Plan]) {
        let currentIDs = Set(plans.map(\.id))
        pending.removeAll { !currentIDs.contains($0.id) }
        for plan in plans {
            let complete = Self.isComplete(plan)
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

    public mutating func acknowledge(_ planID: String) {
        guard pending.contains(where: { $0.id == planID }) else { return }
        pending.removeAll { $0.id == planID }
        dismissedPlanIDs.insert(planID)
    }
}
