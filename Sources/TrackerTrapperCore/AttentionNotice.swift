import Foundation

public struct AttentionNotice: Equatable, Sendable {
    public let id: String
    public let planID: String
    public let subtitle: String
    public let body: String
    public let isStale: Bool

    public static func current(_ snapshot: StoreSnapshot, now: Date = .now) -> [AttentionNotice] {
        snapshot.plans.flatMap { plan in
            let subtitle = plan.displaySubtitle
            var notices = plan.todos.filter { $0.status == .blocked }.map { todo in
                // Encode the composite key so arbitrary stable IDs cannot collide.
                AttentionNotice(id: key([plan.id, todo.id, "blocked"]), planID: plan.id,
                                subtitle: subtitle, body: "Blocked: \(todo.description)", isStale: false)
            }
            for run in snapshot.runs where run.planID == plan.id {
                let message: String
                let stale: Bool
                switch run.status {
                case .waitingForUser: message = "\(run.agent) is waiting for your input."; stale = false
                case .interrupted: message = "\(run.agent) was interrupted."; stale = false
                case .failed: message = "\(run.agent) failed."; stale = false
                case .active where now.timeIntervalSince(run.lastActivityAt) > 15 * 60:
                    message = "No activity from \(run.agent) for 15 minutes."; stale = true
                default: continue
                }
                notices.append(.init(id: key([plan.id, run.id, stale ? "stale" : run.status.rawValue]),
                                     planID: plan.id, subtitle: subtitle, body: message, isStale: stale))
            }
            return notices
        }
    }
    public static func changes(from previous: StoreSnapshot?, to current: StoreSnapshot, now: Date = .now) -> [AttentionNotice] {
        guard let previous else { return [] }
        let oldIDs = Set(Self.current(previous, now: now).map(\.id))
        let knownPlans = Set(previous.plans.map(\.id))
        return Self.current(current, now: now).filter { knownPlans.contains($0.planID) && !oldIDs.contains($0.id) }
    }
    private static func key(_ parts: [String]) -> String {
        // String arrays always encode successfully.
        String(decoding: try! JSONEncoder().encode(parts), as: UTF8.self)
    }
}
