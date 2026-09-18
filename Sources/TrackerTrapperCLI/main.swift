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
        case "get-plan":
            guard let id = value(after: "--plan-id", in: args) else { throw CLIError.usage("get-plan requires --plan-id") }
            let result = await store.read().plans.first { $0.id == id || "\($0.issueNumber)" == id }
            guard let result else { throw StoreError.notFound("plan \(id)") }; try printJSON(result)
        case "start-run":
            guard let planID = value(after: "--plan-id", in: args), let agent = value(after: "--agent", in: args), let session = value(after: "--session-id", in: args) else { throw CLIError.usage("start-run requires --plan-id, --agent and --session-id") }
            try printJSON(await store.startRun(planID: planID, agent: agent, sessionID: session, repositoryPath: value(after: "--repo-path", in: args) ?? FileManager.default.currentDirectoryPath))
        case "update-task":
            guard let runID = value(after: "--run-id", in: args), let todoID = value(after: "--todo-id", in: args), let raw = value(after: "--status", in: args), let status = TodoStatus(rawValue: raw) else { throw CLIError.usage("update-task requires --run-id, --todo-id and --status") }
            try await store.update(runID: runID, todoID: todoID, status: status, message: value(after: "--message", in: args), evidence: values(after: "--evidence", in: args), eventID: value(after: "--event-id", in: args) ?? UUID().uuidString); print("updated")
        case "activity":
            guard let runID = value(after: "--run-id", in: args) else { throw CLIError.usage("activity requires --run-id") }
            try await store.update(runID: runID, todoID: nil, status: nil, message: value(after: "--message", in: args), evidence: values(after: "--evidence", in: args), eventID: value(after: "--event-id", in: args) ?? UUID().uuidString); print("recorded")
        case "finish-run":
            guard let runID = value(after: "--run-id", in: args), let raw = value(after: "--status", in: args), let status = RunStatus(rawValue: raw) else { throw CLIError.usage("finish-run requires --run-id and --status") }
            try await store.finishRun(runID: runID, status: status, message: value(after: "--message", in: args)); print("finished")
        case "snapshot": try printJSON(await store.read())
        default: throw CLIError.usage("unknown command \(command)")
        }
    }

    static func readInput(_ args: [String]) throws -> Data { if let path = value(after: "--input", in: args) { return try Data(contentsOf: URL(fileURLWithPath: path)) }; return FileHandle.standardInput.readDataToEndOfFile() }
    static func value(after flag: String, in args: [String]) -> String? { guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }; return args[index + 1] }
    static func values(after flag: String, in args: [String]) -> [String] { args.enumerated().compactMap { $0.element == flag && args.indices.contains($0.offset + 1) ? args[$0.offset + 1] : nil } }
    static func printJSON<T: Encodable>(_ value: T) throws { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; print(String(decoding: try encoder.encode(value), as: UTF8.self)) }
    static func printHelp() { print("""
    tracker-trapper — local plan/progress bridge
    register-plan --input plan.json
    get-plan --plan-id <id>
    start-run --plan-id <id> --agent <name> --session-id <id> [--repo-path <path>]
    update-task --run-id <id> --todo-id <id> --status <pending|in_progress|blocked|completed|skipped> [--message <text>] [--evidence <value>] [--event-id <id>]
    activity --run-id <id> [--message <text>] [--event-id <id>]
    finish-run --run-id <id> --status <paused|interrupted|finished|failed|waiting_for_user>
    snapshot
    """) }
}
enum CLIError: Error, LocalizedError { case usage(String); var errorDescription: String? { if case .usage(let text) = self { return text }; return nil } }
