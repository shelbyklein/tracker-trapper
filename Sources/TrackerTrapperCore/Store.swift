import Foundation

public actor TrackerStore {
    public let url: URL
    private var snapshot: StoreSnapshot
    private let encoder: JSONEncoder

    public init(url: URL = TrackerStore.defaultURL()) throws {
        self.url = url
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            self.snapshot = try decoder.decode(StoreSnapshot.self, from: data)
        } else {
            self.snapshot = StoreSnapshot()
        }
    }

    public static func defaultURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = environment["TRACKER_TRAPPER_STORE"], !override.isEmpty { return URL(fileURLWithPath: override) }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("TrackerTrapper/store.json")
    }

    public func read() -> StoreSnapshot { snapshot }

    @discardableResult public func register(_ plan: Plan) throws -> Plan {
        if let index = snapshot.plans.firstIndex(where: { $0.repository == plan.repository && $0.issueNumber == plan.issueNumber }) {
            var existing = snapshot.plans[index]
            let incomingIDs = Set(plan.todos.map(\.id))
            let existingIDs = Set(existing.todos.map(\.id))
            guard incomingIDs == existingIDs || existingIDs.isEmpty else { throw StoreError.conflict("plan contains changed todo IDs") }
            existing.title = plan.title; existing.todos = plan.todos; existing.updatedAt = .now; existing.revision += 1
            snapshot.plans[index] = existing; try persist(); return existing
        }
        snapshot.plans.append(plan); try persist(); return plan
    }

    public func startRun(planID: String, agent: String, sessionID: String, repositoryPath: String) throws -> Run {
        guard snapshot.plans.contains(where: { $0.id == planID }) else { throw StoreError.notFound("plan \(planID)") }
        let run = Run(planID: planID, agent: agent, sessionID: sessionID, repositoryPath: repositoryPath)
        snapshot.runs.append(run); appendEvent(ProgressEvent(type: "run_started", planID: planID, runID: run.id)); try persist(); return run
    }

    public func update(runID: String, todoID: String?, status: TodoStatus?, message: String?, evidence: [String] = [], eventID: String = UUID().uuidString) throws {
        if snapshot.events.contains(where: { $0.id == eventID }) { return }
        guard let runIndex = snapshot.runs.firstIndex(where: { $0.id == runID }) else { throw StoreError.notFound("run \(runID)") }
        let run = snapshot.runs[runIndex]
        guard let planIndex = snapshot.plans.firstIndex(where: { $0.id == run.planID }) else { throw StoreError.notFound("plan \(run.planID)") }
        if let todoID, let status, let todoIndex = snapshot.plans[planIndex].todos.firstIndex(where: { $0.id == todoID }) {
            snapshot.plans[planIndex].todos[todoIndex].status = status
            snapshot.plans[planIndex].todos[todoIndex].revision += 1
            snapshot.plans[planIndex].todos[todoIndex].evidence.append(contentsOf: evidence)
            snapshot.plans[planIndex].revision += 1; snapshot.plans[planIndex].updatedAt = .now
        } else if todoID != nil { throw StoreError.notFound("todo \(todoID!)") }
        snapshot.runs[runIndex].currentTodoID = todoID ?? snapshot.runs[runIndex].currentTodoID
        snapshot.runs[runIndex].lastActivityAt = .now; snapshot.runs[runIndex].lastTaskUpdateAt = .now
        appendEvent(ProgressEvent(id: eventID, type: status == nil ? "activity" : "todo_updated", planID: run.planID, runID: runID, todoID: todoID, message: message, evidence: evidence))
        try persist()
    }

    public func finishRun(runID: String, status: RunStatus, message: String? = nil) throws {
        guard let index = snapshot.runs.firstIndex(where: { $0.id == runID }) else { throw StoreError.notFound("run \(runID)") }
        snapshot.runs[index].status = status; snapshot.runs[index].endedAt = .now; snapshot.runs[index].lastActivityAt = .now
        appendEvent(ProgressEvent(type: "run_\(status.rawValue)", planID: snapshot.runs[index].planID, runID: runID, message: message)); try persist()
    }

    public func acknowledgeOutbox() throws { snapshot.outbox.removeAll(); try persist() }

    private func appendEvent(_ event: ProgressEvent) { if !snapshot.events.contains(where: { $0.id == event.id }) { snapshot.events.append(event); snapshot.outbox.append(event) } }

    private func persist() throws {
        let directory = url.deletingLastPathComponent(); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(snapshot); let temp = url.appendingPathExtension("tmp")
        try data.write(to: temp, options: .atomic); if FileManager.default.fileExists(atPath: url.path) { _ = try FileManager.default.replaceItemAt(url, withItemAt: temp) } else { try FileManager.default.moveItem(at: temp, to: url) }
    }
}

public enum StoreError: Error, LocalizedError, Sendable {
    case notFound(String); case conflict(String)
    public var errorDescription: String { switch self { case .notFound(let value): "Not found: \(value)"; case .conflict(let value): "Conflict: \(value)" } }
}
