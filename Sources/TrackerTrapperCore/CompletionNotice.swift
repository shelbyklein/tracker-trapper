import Foundation

public struct CompletionNotice: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    public let body: String

    public static func changes(from previous: StoreSnapshot?, to current: StoreSnapshot) -> [CompletionNotice] {
        guard let previous else { return [] }
        return current.plans.compactMap { plan in
            guard let oldPlan = previous.plans.first(where: { $0.id == plan.id }) else { return nil }
            let completed = plan.todos.filter { todo in
                todo.status == .completed && oldPlan.todos.contains { $0.id == todo.id && $0.status != .completed }
            }
            guard !completed.isEmpty else { return nil }
            return CompletionNotice(
                title: completed.count == 1 ? "Todo completed" : "\(completed.count) todos completed",
                subtitle: plan.displaySubtitle,
                body: completed.map { $0.description }.joined(separator: "\n")
            )
        }
    }
}
