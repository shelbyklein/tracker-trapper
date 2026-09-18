import Foundation
import TrackerTrapperCore

struct PlanInput: Codable {
    var id: String?
    var repository: String
    var issueNumber: Int
    var issueURL: String
    var title: String
    var todos: [TodoInput]
}
struct TodoInput: Codable { var id: String; var description: String; var acceptance: String? }
struct LocalPlanInput: Codable {
    var title: String
    var todos: [TodoInput]
    var workspacePath: String?
    var creationRequestKey: String
    var client: String?
    var sessionID: String?
    var agent: String?
}

@main
struct TrackerTrapperCLI {
    static func main() async {
        do { try await run(Array(CommandLine.arguments.dropFirst())) }
        catch { fputs("tracker-trapper: \(error.localizedDescription)\n", stderr); exit(1) }
    }

    static func run(_ args: [String]) async throws {
        guard let command = args.first else { printHelp(); return }
        let store = try TrackerStore()
        switch command {
        case "--help", "help": printHelp()
        case "register-plan":
            let data = try readInput(args)
            let input = try JSONDecoder().decode(PlanInput.self, from: data)
            let plan = Plan(id: input.id ?? UUID().uuidString, repository: input.repository, issueNumber: input.issueNumber, issueURL: input.issueURL, title: input.title, todos: input.todos.map { Todo(id: $0.id, description: $0.description, acceptance: $0.acceptance ?? "") })
            try printJSON(await store.register(plan))
        case "register-local-plan":
            let input = try JSONDecoder().decode(LocalPlanInput.self, from: readInput(args))
            let todos = input.todos.map { Todo(id: $0.id, description: $0.description, acceptance: $0.acceptance ?? "") }
            try printJSON(await store.registerLocal(title: input.title, todos: todos, workspacePath: input.workspacePath, creationRequestKey: input.creationRequestKey))
        case "import-issue":
            guard let repository = value(after: "--repo", in: args), let issue = value(after: "--issue", in: args), let issueNumber = Int(issue) else { throw CLIError.usage("import-issue requires --repo owner/name and --issue number") }
            let imported = try importIssue(repository: repository, issueNumber: issueNumber)
            try printJSON(await store.register(imported))
        case "create-issue":
            guard let repository = value(after: "--repo", in: args), let title = value(after: "--title", in: args), let bodyFile = value(after: "--body-file", in: args) else {
                throw CLIError.usage("create-issue requires --repo, --title and --body-file")
            }
            let issueURL = try createIssue(repository: repository, title: title, bodyFile: bodyFile)
            guard let issueNumber = Int(URL(string: issueURL)?.pathComponents.last ?? "") else {
                throw CLIError.usage("GitHub created the issue but returned an unparseable URL: \(issueURL). Retry with import-issue --repo \(repository) --issue <number>")
            }
            do {
                let imported = try importIssue(repository: repository, issueNumber: issueNumber)
                let registered = try await store.register(imported)
                try await store.clearRegistrationRetry(id: "github:\(repository)#\(issueNumber)")
                try printJSON(registered)
            } catch {
                try await store.enqueueRegistrationRetry(RegistrationRetry(repository: repository, issueNumber: issueNumber, issueURL: issueURL, reason: error.localizedDescription))
                throw CLIError.usage("GitHub issue created at \(issueURL), but local registration failed: \(error.localizedDescription). Retry with import-issue --repo \(repository) --issue \(issueNumber)")
            }
        case "retry-registrations":
            let retries = try await store.read().registrationRetries
            var failures: [String] = []
            for retry in retries {
                do {
                    let imported = try importIssue(repository: retry.repository, issueNumber: retry.issueNumber)
                    _ = try await store.register(imported)
                    try await store.clearRegistrationRetry(id: retry.id)
                    print("registered \(retry.issueURL)")
                } catch {
                    failures.append("\(retry.repository)#\(retry.issueNumber): \(error.localizedDescription)")
                }
            }
            if !failures.isEmpty { throw CLIError.usage("registration retries still pending: \(failures.joined(separator: "; "))") }
        case "get-plan":
            guard let id = value(after: "--plan-id", in: args) else { throw CLIError.usage("get-plan requires --plan-id") }
            let result = try await store.read().plans.first { $0.id == id || "\($0.issueNumber)" == id }
            guard let result else { throw StoreError.notFound("plan \(id)") }; try printJSON(result)
        case "list-local-plans":
            try printJSON(try await store.read().plans.filter { $0.source == .local })
        case "tracker":
            guard let action = args.dropFirst().first else { throw CLIError.usage("tracker requires on, off, start or status") }
            switch action {
            case "on", "off":
                try printJSON(await store.setTrackingSettings(TrackingSettings(askAtSessionStart: action == "on")))
            case "status":
                let snapshot = try await store.read()
                if let client = value(after: "--client", in: args), let sessionID = value(after: "--session-id", in: args) {
                    struct Status: Encodable { let settings: TrackingSettings; let session: SessionTracking? }
                    try printJSON(Status(settings: snapshot.trackingSettings, session: snapshot.sessionTracking.first { $0.client == client && $0.sessionID == sessionID }))
                } else { try printJSON(snapshot.trackingSettings) }
            case "start":
                let input = try JSONDecoder().decode(LocalPlanInput.self, from: readInput(args))
                guard let client = input.client, let sessionID = input.sessionID, let agent = input.agent else {
                    throw CLIError.usage("tracker start input requires client, sessionID and agent")
                }
                let plan = try await store.registerLocal(title: input.title, todos: input.todos.map { Todo(id: $0.id, description: $0.description, acceptance: $0.acceptance ?? "") }, workspacePath: input.workspacePath, creationRequestKey: input.creationRequestKey)
                let run = try await store.startRun(planID: plan.id, agent: agent, sessionID: sessionID, repositoryPath: input.workspacePath ?? FileManager.default.currentDirectoryPath)
                _ = try await store.setSessionTracking(SessionTracking(client: client, sessionID: sessionID, decision: .accepted, planID: plan.id, runID: run.id, creationRequestKey: input.creationRequestKey))
                struct Started: Encodable { let plan: Plan; let run: Run }
                try printJSON(Started(plan: plan, run: run))
            default: throw CLIError.usage("tracker requires on, off, start or status")
            }
        case "session-tracking":
            guard let client = value(after: "--client", in: args), let sessionID = value(after: "--session-id", in: args) else { throw CLIError.usage("session-tracking requires --client and --session-id") }
            if let raw = value(after: "--decision", in: args), let decision = SessionTrackingDecision(rawValue: raw) {
                try printJSON(await store.setSessionTracking(SessionTracking(client: client, sessionID: sessionID, decision: decision, planID: value(after: "--plan-id", in: args), runID: value(after: "--run-id", in: args), creationRequestKey: value(after: "--creation-request-key", in: args))))
            } else { try printJSON(await store.sessionTracking(client: client, sessionID: sessionID)) }
        case "start-run":
            guard let planID = value(after: "--plan-id", in: args), let agent = value(after: "--agent", in: args), let session = value(after: "--session-id", in: args) else { throw CLIError.usage("start-run requires --plan-id, --agent and --session-id") }
            try printJSON(await store.startRun(planID: planID, agent: agent, sessionID: session, repositoryPath: value(after: "--repo-path", in: args) ?? FileManager.default.currentDirectoryPath))
        case "update-task", "start-task", "complete-task":
            guard let runID = value(after: "--run-id", in: args), let todoID = value(after: "--todo-id", in: args) else { throw CLIError.usage("task update requires --run-id and --todo-id") }
            let suppliedStatus = value(after: "--status", in: args).flatMap(TodoStatus.init(rawValue:))
            guard command != "update-task" || suppliedStatus != nil else { throw CLIError.usage("update-task requires --status") }
            let effectiveStatus = command == "start-task" ? TodoStatus.inProgress : command == "complete-task" ? TodoStatus.completed : suppliedStatus!
            try await store.update(runID: runID, todoID: todoID, status: effectiveStatus, message: value(after: "--message", in: args), evidence: values(after: "--evidence", in: args), eventID: value(after: "--event-id", in: args) ?? UUID().uuidString, nextTodoID: value(after: "--next-todo-id", in: args)); print("updated")
        case "set-next-task":
            guard let runID = value(after: "--run-id", in: args),
                  let nextID = value(after: "--next-todo-id", in: args) else {
                throw CLIError.usage("set-next-task requires --run-id and --next-todo-id (empty string clears)")
            }
            try await store.update(runID: runID, todoID: nil, status: nil, message: "Next task selection", nextTodoID: nextID)
            print("updated")
        case "activity":
            guard let runID = value(after: "--run-id", in: args) else { throw CLIError.usage("activity requires --run-id") }
            try await store.update(runID: runID, todoID: nil, status: nil, message: value(after: "--message", in: args), evidence: values(after: "--evidence", in: args), eventID: value(after: "--event-id", in: args) ?? UUID().uuidString, nextTodoID: value(after: "--next-todo-id", in: args)); print("recorded")
        case "record-sync":
            guard let planID = value(after: "--plan-id", in: args), let hash = value(after: "--hash", in: args) else { throw CLIError.usage("record-sync requires --plan-id and --hash") }
            try await store.recordSync(planID: planID, hash: hash); print("recorded")
        case "ack-outbox":
            try await store.acknowledgeOutbox(); print("acknowledged")
        case "finish-run":
            guard let runID = value(after: "--run-id", in: args), let raw = value(after: "--status", in: args), let status = RunStatus(rawValue: raw) else { throw CLIError.usage("finish-run requires --run-id and --status") }
            try await store.finishRun(runID: runID, status: status, message: value(after: "--message", in: args)); print("finished")
        case "snapshot": try printJSON(try await store.read())
        case "watch-session":
            guard let runID = value(after: "--run-id", in: args), let path = value(after: "--source", in: args),
                  let raw = value(after: "--format", in: args), let format = SessionFormat(rawValue: raw) else {
                throw CLIError.usage("watch-session requires --run-id, --source /absolute/session.jsonl, --format codex|claude")
            }
            try printJSON(await SessionWatcher(store: store).link(runID: runID, sourcePath: path, format: format))
        case "unwatch-session":
            guard let runID = value(after: "--run-id", in: args) else { throw CLIError.usage("unwatch-session requires --run-id") }
            try await SessionWatcher(store: store).unlink(runID: runID); print("unlinked")
        case "watch-status": try printJSON(await SessionWatcher(store: store).reports())
        case "watch-once": try printJSON(await SessionWatcher(store: store).poll())
        default: throw CLIError.usage("unknown command \(command)")
        }
    }

    static func readInput(_ args: [String]) throws -> Data { if let path = value(after: "--input", in: args) { return try Data(contentsOf: URL(fileURLWithPath: path)) }; return FileHandle.standardInput.readDataToEndOfFile() }
    static func importIssue(repository: String, issueNumber: Int) throws -> Plan {
        let data = try runProcess("gh", arguments: ["issue", "view", String(issueNumber), "--repo", repository, "--json", "title,body,url"])
        struct Issue: Decodable { let title: String; let body: String; let url: String }
        let issue = try JSONDecoder().decode(Issue.self, from: data)
        let todos = GitHubChecklist.parse(issue.body)
        return Plan(id: "github:\(repository)#\(issueNumber)", repository: repository, issueNumber: issueNumber, issueURL: issue.url, title: issue.title, todos: todos)
    }
    static func createIssue(repository: String, title: String, bodyFile: String) throws -> String {
        let data = try runProcess("gh", arguments: ["issue", "create", "--repo", repository, "--title", title, "--body-file", bodyFile])
        let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = output.split(whereSeparator: \ .isWhitespace).last.map(String.init), url.contains("/issues/") else {
            throw CLIError.usage("gh issue create returned no issue URL: \(output)")
        }
        return url
    }
    static func runProcess(_ executable: String, arguments: [String]) throws -> Data {
        let process = Process(); let output = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env"); process.arguments = [executable] + arguments; process.standardOutput = output; process.standardError = output
        try process.run(); let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit(); guard process.terminationStatus == 0 else { throw CLIError.usage(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) }; return data
    }
    static func value(after flag: String, in args: [String]) -> String? { guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }; return args[index + 1] }
    static func values(after flag: String, in args: [String]) -> [String] { args.enumerated().compactMap { $0.element == flag && args.indices.contains($0.offset + 1) ? args[$0.offset + 1] : nil } }
    static func printJSON<T: Encodable>(_ value: T) throws { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; print(String(decoding: try encoder.encode(value), as: UTF8.self)) }
    static func printHelp() { print("""
    tracker-trapper — local plan/progress bridge
    register-plan --input plan.json
    register-local-plan --input local-plan.json
    list-local-plans
    tracker on|off|status
    tracker start --input local-plan-with-session.json
    session-tracking --client <codex|claude> --session-id <id> [--decision <pending|declined|accepted>]
    import-issue --repo owner/name --issue 123
    create-issue --repo owner/name --title "Title" --body-file plan.md
    retry-registrations
    set-next-task --run-id <id> --next-todo-id <todo-id|empty-string>
    get-plan --plan-id <id>
    start-run --plan-id <id> --agent <name> --session-id <id> [--repo-path <path>]
    update-task --run-id <id> --todo-id <id> --status <pending|in_progress|blocked|completed|skipped> [--message <text>] [--evidence <value>] [--event-id <id>]
    start-task --run-id <id> --todo-id <id> [--message <text>]
    complete-task --run-id <id> --todo-id <id> [--message <text>] [--evidence <value>]
    activity --run-id <id> [--message <text>] [--event-id <id>]
    finish-run --run-id <id> --status <paused|interrupted|finished|failed|waiting_for_user>
    snapshot
    watch-session --run-id <id> --source /absolute/session.jsonl --format codex|claude
    unwatch-session --run-id <id>
    watch-status
    watch-once
    ack-outbox
    """) }
}
enum CLIError: Error, LocalizedError { case usage(String); var errorDescription: String? { if case .usage(let text) = self { return text }; return nil } }
