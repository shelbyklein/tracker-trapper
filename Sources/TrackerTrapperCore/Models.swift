import Foundation

public enum TodoStatus: String, Codable, CaseIterable, Sendable {
    case pending, inProgress = "in_progress", blocked, completed, skipped
}

public enum RunStatus: String, Codable, Sendable {
    case active, waitingForUser = "waiting_for_user", paused, interrupted, finished, failed
}

public enum PlanSource: String, Codable, Sendable {
    case github, local
}

public enum SessionTrackingDecision: String, Codable, Sendable {
    case pending, declined, accepted
}

public struct TrackingSettings: Codable, Equatable, Sendable {
    public var askAtSessionStart: Bool

    public init(askAtSessionStart: Bool = false) {
        self.askAtSessionStart = askAtSessionStart
    }
}

public struct SessionTracking: Codable, Identifiable, Equatable, Sendable {
    public var id: String { "\(client):\(sessionID)" }
    public let client: String
    public let sessionID: String
    public var decision: SessionTrackingDecision
    public var planID: String?
    public var runID: String?
    public var creationRequestKey: String?
    public var updatedAt: Date

    public init(client: String, sessionID: String, decision: SessionTrackingDecision, planID: String? = nil, runID: String? = nil, creationRequestKey: String? = nil, updatedAt: Date = .now) {
        self.client = client; self.sessionID = sessionID; self.decision = decision
        self.planID = planID; self.runID = runID; self.creationRequestKey = creationRequestKey; self.updatedAt = updatedAt
    }
}

public struct Todo: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var description: String
    public var acceptance: String
    public var status: TodoStatus
    public var parentID: String?
    public var stage: String?
    public var evidence: [String]
    public var revision: Int

    public init(id: String, description: String, acceptance: String = "", status: TodoStatus = .pending, parentID: String? = nil, evidence: [String] = [], revision: Int = 0, stage: String? = nil) {
        self.stage = stage
        self.id = id; self.description = description; self.acceptance = acceptance; self.status = status
        self.parentID = parentID; self.evidence = evidence; self.revision = revision
    }
}

public struct Plan: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var repository: String
    public var issueNumber: Int
    public var issueURL: String
    public var title: String
    public var todos: [Todo]
    public var revision: Int
    public var updatedAt: Date
    public var lastSyncedProgressHash: String?
    public var nextTodoID: String?
    public var source: PlanSource
    public var workspacePath: String?
    public var creationRequestKey: String?

    public var nextTodo: Todo? {
        todos.first { $0.id == nextTodoID && $0.status != .completed && $0.status != .skipped }
    }

    public var displaySubtitle: String {
        source == .github ? "\(repository) #\(issueNumber)" : "Local"
    }

    public var isGitHub: Bool { source == .github }

    public init(id: String = UUID().uuidString, repository: String, issueNumber: Int, issueURL: String, title: String, todos: [Todo], revision: Int = 0, updatedAt: Date = .now, lastSyncedProgressHash: String? = nil) {
        self.id = id; self.repository = repository; self.issueNumber = issueNumber; self.issueURL = issueURL
        self.title = title; self.todos = todos; self.revision = revision; self.updatedAt = updatedAt; self.lastSyncedProgressHash = lastSyncedProgressHash
        self.source = .github; self.workspacePath = nil; self.creationRequestKey = nil
    }

    public init(localID: String = "local:\(UUID().uuidString)", title: String, todos: [Todo], workspacePath: String? = nil, creationRequestKey: String, revision: Int = 0, updatedAt: Date = .now) {
        self.id = localID; self.repository = ""; self.issueNumber = 0; self.issueURL = ""
        self.title = title; self.todos = todos; self.revision = revision; self.updatedAt = updatedAt
        self.lastSyncedProgressHash = nil; self.nextTodoID = nil; self.source = .local
        self.workspacePath = workspacePath; self.creationRequestKey = creationRequestKey
    }

    private enum CodingKeys: String, CodingKey {
        case id, repository, issueNumber, issueURL, title, todos, revision, updatedAt, lastSyncedProgressHash, nextTodoID
        case source, workspacePath, creationRequestKey
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        repository = try values.decodeIfPresent(String.self, forKey: .repository) ?? ""
        issueNumber = try values.decodeIfPresent(Int.self, forKey: .issueNumber) ?? 0
        issueURL = try values.decodeIfPresent(String.self, forKey: .issueURL) ?? ""
        title = try values.decode(String.self, forKey: .title)
        todos = try values.decode([Todo].self, forKey: .todos)
        revision = try values.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        lastSyncedProgressHash = try values.decodeIfPresent(String.self, forKey: .lastSyncedProgressHash)
        nextTodoID = try values.decodeIfPresent(String.self, forKey: .nextTodoID)
        source = try values.decodeIfPresent(PlanSource.self, forKey: .source) ?? .github
        workspacePath = try values.decodeIfPresent(String.self, forKey: .workspacePath)
        creationRequestKey = try values.decodeIfPresent(String.self, forKey: .creationRequestKey)
    }
}

public struct Run: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let planID: String
    public var agent: String
    public var sessionID: String
    public var repositoryPath: String
    public var status: RunStatus
    public var startedAt: Date
    public var endedAt: Date?
    public var lastActivityAt: Date
    public var lastTaskUpdateAt: Date?
    public var currentTodoID: String?

    public init(id: String = UUID().uuidString, planID: String, agent: String, sessionID: String, repositoryPath: String, status: RunStatus = .active, startedAt: Date = .now, endedAt: Date? = nil, lastActivityAt: Date = .now, lastTaskUpdateAt: Date? = nil, currentTodoID: String? = nil) {
        self.id = id; self.planID = planID; self.agent = agent; self.sessionID = sessionID; self.repositoryPath = repositoryPath
        self.status = status; self.startedAt = startedAt; self.endedAt = endedAt; self.lastActivityAt = lastActivityAt
        self.lastTaskUpdateAt = lastTaskUpdateAt; self.currentTodoID = currentTodoID
    }
}

public struct ProgressEvent: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let type: String
    public let planID: String
    public let runID: String?
    public let todoID: String?
    public let message: String?
    public let evidence: [String]
    public let createdAt: Date

    public init(id: String = UUID().uuidString, type: String, planID: String, runID: String? = nil, todoID: String? = nil, message: String? = nil, evidence: [String] = [], createdAt: Date = .now) {
        self.id = id; self.type = type; self.planID = planID; self.runID = runID; self.todoID = todoID
        self.message = message; self.evidence = evidence; self.createdAt = createdAt
    }
}

public struct RegistrationRetry: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let repository: String
    public let issueNumber: Int
    public let issueURL: String
    public let reason: String
    public let createdAt: Date

    public init(repository: String, issueNumber: Int, issueURL: String, reason: String, createdAt: Date = .now) {
        self.id = "github:\(repository)#\(issueNumber)"; self.repository = repository; self.issueNumber = issueNumber
        self.issueURL = issueURL; self.reason = reason; self.createdAt = createdAt
    }
}

public struct StoreSnapshot: Codable, Equatable, Sendable {
    public var plans: [Plan]
    public var runs: [Run]
    public var events: [ProgressEvent]
    public var outbox: [ProgressEvent]
    public var registrationRetries: [RegistrationRetry]
    public var schemaVersion: Int
    public var trackingSettings: TrackingSettings
    public var sessionTracking: [SessionTracking]

    public init(plans: [Plan] = [], runs: [Run] = [], events: [ProgressEvent] = [], outbox: [ProgressEvent] = [], registrationRetries: [RegistrationRetry] = [], schemaVersion: Int = 2, trackingSettings: TrackingSettings = TrackingSettings(), sessionTracking: [SessionTracking] = []) {
        self.plans = plans; self.runs = runs; self.events = events; self.outbox = outbox; self.registrationRetries = registrationRetries; self.schemaVersion = schemaVersion
        self.trackingSettings = trackingSettings; self.sessionTracking = sessionTracking
    }

    private enum CodingKeys: String, CodingKey { case plans, runs, events, outbox, registrationRetries, schemaVersion, trackingSettings, sessionTracking }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        plans = try values.decode([Plan].self, forKey: .plans); runs = try values.decode([Run].self, forKey: .runs)
        events = try values.decode([ProgressEvent].self, forKey: .events); outbox = try values.decode([ProgressEvent].self, forKey: .outbox)
        registrationRetries = try values.decodeIfPresent([RegistrationRetry].self, forKey: .registrationRetries) ?? []
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        trackingSettings = try values.decodeIfPresent(TrackingSettings.self, forKey: .trackingSettings) ?? TrackingSettings()
        sessionTracking = try values.decodeIfPresent([SessionTracking].self, forKey: .sessionTracking) ?? []
    }
}
