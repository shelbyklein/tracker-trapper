import Foundation
import Darwin

public actor TrackerStore {
    public nonisolated let url: URL
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

    public func read() throws -> StoreSnapshot {
        try transaction { snapshot }
    }

    @discardableResult public func register(_ plan: Plan) throws -> Plan {
        try transaction {
        if let index = snapshot.plans.firstIndex(where: { $0.repository == plan.repository && $0.issueNumber == plan.issueNumber }) {
            var existing = snapshot.plans[index]
            let incomingIDs = Set(plan.todos.map(\.id))
            let existingIDs = Set(existing.todos.map(\.id))
            guard incomingIDs == existingIDs || existingIDs.isEmpty else { throw StoreError.conflict("plan contains changed todo IDs") }
            existing.title = plan.title
            existing.todos = plan.todos.map { incoming in
                guard var saved = existing.todos.first(where: { $0.id == incoming.id }) else { return incoming }
                saved.description = incoming.description; saved.acceptance = incoming.acceptance
                return saved
            }
            existing.updatedAt = .now; existing.revision += 1
            snapshot.plans[index] = existing; try persist(); return existing
        }
        snapshot.plans.append(plan); try persist(); return plan
        }
    }

    /// Pull the authoritative checklist without deleting historical IDs or
    /// resetting newer local progress that has not reached GitHub yet.
    public func reconcileGitHubChecklist(planID: String, title: String, todos: [Todo]) throws {
        try transaction {
            guard let index = snapshot.plans.firstIndex(where: { $0.id == planID }) else { throw StoreError.notFound(planID) }
            guard Set(todos.map(\.id)).count == todos.count else { throw StoreError.conflict("GitHub checklist contains duplicate todo IDs") }
            var plan = snapshot.plans[index]
            let before = plan
            plan.title = title
            for incoming in todos {
                if let todoIndex = plan.todos.firstIndex(where: { $0.id == incoming.id }) {
                    plan.todos[todoIndex].description = incoming.description
                    if !incoming.acceptance.isEmpty { plan.todos[todoIndex].acceptance = incoming.acceptance }
                    if incoming.status == .completed && plan.todos[todoIndex].status == .pending {
                        plan.todos[todoIndex].status = .completed
                        plan.todos[todoIndex].evidence.append("GitHub checklist reports completion: \(plan.issueURL)")
                        plan.todos[todoIndex].revision += 1
                    }
                } else {
                    var added = incoming
                    if added.status == .completed { added.evidence = ["GitHub checklist reports completion: \(plan.issueURL)"] }
                    plan.todos.append(added)
                }
            }
            guard plan != before else { return }
            plan.revision += 1; plan.updatedAt = .now
            snapshot.plans[index] = plan
            snapshot.events.append(ProgressEvent(type: "github_checklist_refreshed", planID: planID, message: "Refreshed \(todos.count) GitHub checklist items; retained local evidence and historical IDs"))
            try persist()
        }
    }

    public func enqueueRegistrationRetry(_ retry: RegistrationRetry) throws {
        try transaction {
        if !snapshot.registrationRetries.contains(where: { $0.id == retry.id }) { snapshot.registrationRetries.append(retry); try persist() }
        }
    }

    public func clearRegistrationRetry(id: String) throws {
        try transaction {
        snapshot.registrationRetries.removeAll { $0.id == id }; try persist()
        }
    }

    public func startRun(planID: String, agent: String, sessionID: String, repositoryPath: String) throws -> Run {
        try transaction {
        guard snapshot.plans.contains(where: { $0.id == planID }) else { throw StoreError.notFound("plan \(planID)") }
        let run = Run(planID: planID, agent: agent, sessionID: sessionID, repositoryPath: repositoryPath)
        snapshot.runs.append(run); appendEvent(ProgressEvent(type: "run_started", planID: planID, runID: run.id)); try persist(); return run
        }
    }

    public func update(runID: String, todoID: String?, status: TodoStatus?, message: String?, evidence: [String] = [], eventID: String = UUID().uuidString, nextTodoID: String? = nil) throws {
        try transaction {
        if snapshot.events.contains(where: { $0.id == eventID }) { return }
        guard let runIndex = snapshot.runs.firstIndex(where: { $0.id == runID }) else { throw StoreError.notFound("run \(runID)") }
        let run = snapshot.runs[runIndex]
        guard let planIndex = snapshot.plans.firstIndex(where: { $0.id == run.planID }) else { throw StoreError.notFound("plan \(run.planID)") }
        let previousNextTodoID = snapshot.plans[planIndex].nextTodoID
        if let todoID, let status, let todoIndex = snapshot.plans[planIndex].todos.firstIndex(where: { $0.id == todoID }) {
            snapshot.plans[planIndex].todos[todoIndex].status = status
            snapshot.plans[planIndex].todos[todoIndex].revision += 1
            snapshot.plans[planIndex].todos[todoIndex].evidence.append(contentsOf: evidence)
            snapshot.plans[planIndex].revision += 1; snapshot.plans[planIndex].updatedAt = .now
        } else if todoID != nil { throw StoreError.notFound("todo \(todoID!)") }
        // Omission preserves the selection; an empty string explicitly clears it.
        if let nextTodoID {
            if !nextTodoID.isEmpty {
                guard let next = snapshot.plans[planIndex].todos.first(where: { $0.id == nextTodoID }) else {
                    throw StoreError.notFound("next todo \(nextTodoID)")
                }
                guard next.status != .completed && next.status != .skipped else {
                    throw StoreError.conflict("next todo must be unfinished")
                }
            }
            snapshot.plans[planIndex].nextTodoID = nextTodoID.isEmpty ? nil : nextTodoID
            snapshot.plans[planIndex].revision += 1
            snapshot.plans[planIndex].updatedAt = .now
        } else if snapshot.plans[planIndex].nextTodoID == todoID,
                  status == .completed || status == .skipped {
            snapshot.plans[planIndex].nextTodoID = nil
        }
        snapshot.runs[runIndex].currentTodoID = todoID ?? snapshot.runs[runIndex].currentTodoID
        snapshot.runs[runIndex].lastActivityAt = .now
        if (todoID != nil && status != nil) || nextTodoID != nil { snapshot.runs[runIndex].lastTaskUpdateAt = .now }
        appendEvent(ProgressEvent(id: eventID, type: status == nil ? "activity" : "todo_updated", planID: run.planID, runID: runID, todoID: todoID, message: message, evidence: evidence))
        if nextTodoID != nil || previousNextTodoID != snapshot.plans[planIndex].nextTodoID {
            // Existing clients preserve these event fields even if their older
            // Plan decoder drops nextTodoID while writing unrelated progress.
            appendEvent(ProgressEvent(id: "\(eventID):next", type: "next_task_selected", planID: run.planID, runID: runID, todoID: snapshot.plans[planIndex].nextTodoID))
        }
        try persist()
        }
    }

    public func finishRun(runID: String, status: RunStatus, message: String? = nil) throws {
        try transaction {
        guard let index = snapshot.runs.firstIndex(where: { $0.id == runID }) else { throw StoreError.notFound("run \(runID)") }
        let planID = snapshot.runs[index].planID
        let unresolved = snapshot.plans.first(where: { $0.id == planID })?.todos.filter { $0.status != .completed && $0.status != .skipped }.map(\.id) ?? []
        let reconciliation = unresolved.isEmpty ? message : message ?? "unresolved todos: \(unresolved.joined(separator: ", "))"
        snapshot.runs[index].status = status; snapshot.runs[index].endedAt = .now; snapshot.runs[index].lastActivityAt = .now
        appendEvent(ProgressEvent(type: "run_\(status.rawValue)", planID: planID, runID: runID, message: reconciliation)); try persist()
        }
    }

    public func acknowledgeOutbox() throws { try transaction { snapshot.outbox.removeAll(); try persist() } }

    public func recordSync(planID: String, hash: String) throws {
        try transaction {
        guard let index = snapshot.plans.firstIndex(where: { $0.id == planID }) else { throw StoreError.notFound("plan \(planID)") }
        snapshot.plans[index].lastSyncedProgressHash = hash; try persist()
        }
    }

    /// Observations use source timestamps, not poll time. A monitor waking up
    /// must never make an idle agent appear active or reopen a finished run.
    public func observe(runID: String, observations: [SessionObservation], source: String) throws {
        guard !observations.isEmpty else { return }
        try transaction {
            guard let runIndex = snapshot.runs.firstIndex(where: { $0.id == runID }) else { throw StoreError.notFound(runID) }
            guard snapshot.runs[runIndex].status == .active else { return }
            let planID = snapshot.runs[runIndex].planID
            guard let planIndex = snapshot.plans.firstIndex(where: { $0.id == planID }) else { throw StoreError.notFound(planID) }
            let unseen = observations.filter { observation in !snapshot.events.contains { $0.id == observation.id } }
            guard !unseen.isEmpty else { return }
            for observation in unseen {
                for completion in observation.completions {
                    guard let todoIndex = snapshot.plans[planIndex].todos.firstIndex(where: { $0.id == completion.todoID }),
                          snapshot.plans[planIndex].todos[todoIndex].status != .completed,
                          snapshot.plans[planIndex].todos[todoIndex].status != .skipped else { continue }
                    let newerExplicitUpdate = snapshot.events.contains { $0.planID == planID && $0.todoID == completion.todoID && $0.createdAt >= observation.occurredAt }
                    guard !newerExplicitUpdate else { continue }
                    let evidence = "Agent-reported completion via \(source): \(completion.evidence)"
                    snapshot.plans[planIndex].todos[todoIndex].status = .completed
                    if snapshot.plans[planIndex].nextTodoID == completion.todoID {
                        snapshot.plans[planIndex].nextTodoID = nil
                        appendEvent(ProgressEvent(id: "\(observation.id):next", type: "next_task_selected", planID: planID, runID: runID))
                    }
                    snapshot.plans[planIndex].todos[todoIndex].revision += 1
                    snapshot.plans[planIndex].todos[todoIndex].evidence.append(evidence)
                    snapshot.plans[planIndex].revision += 1
                    snapshot.plans[planIndex].updatedAt = max(snapshot.plans[planIndex].updatedAt, observation.occurredAt)
                    snapshot.runs[runIndex].lastTaskUpdateAt = max(snapshot.runs[runIndex].lastTaskUpdateAt ?? .distantPast, observation.occurredAt)
                    appendEvent(ProgressEvent(id: "\(observation.id):\(completion.todoID)", type: "observed_completion", planID: planID, runID: runID, todoID: completion.todoID, message: evidence, evidence: [evidence], createdAt: observation.occurredAt))
                }
                snapshot.runs[runIndex].lastActivityAt = max(snapshot.runs[runIndex].lastActivityAt, observation.occurredAt)
                // Activity belongs in the local timeline, not the GitHub outbox.
                snapshot.events.append(ProgressEvent(id: observation.id, type: "session_activity", planID: planID, runID: runID, message: observation.message, evidence: [source], createdAt: observation.occurredAt))
            }
            try persist()
        }
    }

    // Lock a stable sidecar inode, not the JSON file replaced by atomic writes.
    // Keep reload, validation, mutation and persistence in one synchronous lock.
    private func transaction<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = Darwin.open(url.appendingPathExtension("lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { Darwin.close(descriptor) }
        while flock(descriptor, LOCK_EX) != 0 {
            if errno != EINTR { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        defer { flock(descriptor, LOCK_UN) }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        if FileManager.default.fileExists(atPath: url.path) {
            snapshot = try decoder.decode(StoreSnapshot.self, from: Data(contentsOf: url))
        } else {
            snapshot = StoreSnapshot()
        }
        // Reconstruct the selection after a write by a pre-next-task client.
        for index in snapshot.plans.indices {
            if let selection = snapshot.events.last(where: { $0.planID == snapshot.plans[index].id && $0.type == "next_task_selected" }) {
                snapshot.plans[index].nextTodoID = selection.todoID
                if snapshot.plans[index].nextTodo == nil { snapshot.plans[index].nextTodoID = nil }
            }
        }
        let before = snapshot
        do { return try body() }
        catch { snapshot = before; throw error }
    }

    private func appendEvent(_ event: ProgressEvent) { if !snapshot.events.contains(where: { $0.id == event.id }) { snapshot.events.append(event); snapshot.outbox.append(event) } }

    private func persist() throws {
        let directory = url.deletingLastPathComponent(); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(snapshot); let temp = url.appendingPathExtension("tmp")
        try data.write(to: temp, options: .atomic); if FileManager.default.fileExists(atPath: url.path) { _ = try FileManager.default.replaceItemAt(url, withItemAt: temp) } else { try FileManager.default.moveItem(at: temp, to: url) }
    }
}

public enum StoreError: Error, LocalizedError, Sendable {
    case notFound(String); case conflict(String)
    public var errorDescription: String? { switch self { case .notFound(let value): "Not found: \(value)"; case .conflict(let value): "Conflict: \(value)" } }
}
